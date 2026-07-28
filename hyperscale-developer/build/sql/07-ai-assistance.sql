/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   07-ai-assistance.sql : AI layer 2 of 2 — clinical assistance proc
   Run order            : 7 of 7  (after 06-ai-embeddings.sql)

   clinical.GenerateClinicalAssistance stitches the whole in-engine AI story
   into one call the app / DAB / MCP can invoke:

     1. Pull the live chart for an encounter (clinical.vPatientChart)
     2. Embed a short "case summary" of that chart and run VECTOR_SEARCH over
        clinical.ClinicalNoteEmbeddings to find the most semantically similar
        historical notes (retrieval-augmented grounding — RAG, in the engine)
     3. Send chart + similar-case context to the Collier Health Foundry chat
        deployment via sp_invoke_external_rest_endpoint
     4. Parse the JSON answer and write an auditable row to
        clinical.AIAssistanceLog

   ASSISTANCE, NOT AUTOMATION:
     The engine ASSISTS the attending — it does not decide. It returns a
     *suggested* triage flag (for the attending to confirm or override) plus a
     short, grounded summary of considerations, and it surfaces the note ids it
     was grounded on so the clinician can check its work. The proc reads only;
     it never changes the chart, and it logs every call for review.

   Why Hyperscale matters here:
     Retrieval (VECTOR_SEARCH over the note corpus), the live OLTP chart read,
     and the audit write all happen in ONE database, against the SAME rows the
     clinicians are editing — no ETL to a separate vector store, no eventual-
     consistency gap. On a non-Hyperscale tier the note corpus + 108M-row
     Observation history would push you to shard or offload search to an
     external service; here it stays one query surface.

   PREREQUISITES:
     * 06-ai-embeddings.sql already run (external model + embeddings + index).
     * A Foundry chat/reasoning deployment (e.g. gpt-5) on the SAME Foundry
       resource, reusing the credential created in 06 (managed identity, passwordless).

   All data created by these scripts is fully synthetic. No real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Audit log: one row per assistance call ---------------------------- */
/* Every AI assistance call is captured with its inputs, the model's raw        */
/* response, and the parsed result, so a clinician (or compliance) can review    */
/* what the engine suggested and why. This is an APPEND-ONLY LEDGER table: the    */
/* engine only ever INSERTs, and the ledger makes the trail tamper-evident        */
/* (UPDATE / DELETE / TRUNCATE are blocked even for db_owner) and cryptographically*/
/* verifiable via the database ledger digest — the "Secure it" audit story.        */
IF OBJECT_ID('clinical.AIAssistanceLog', 'U') IS NULL
BEGIN
    CREATE TABLE clinical.AIAssistanceLog
    (
        AssistanceId         BIGINT         NOT NULL IDENTITY(1, 1),
        EncounterId          INT            NOT NULL,
        PatientId            INT            NOT NULL,
        ModelDeployment      NVARCHAR(64)   NOT NULL,
        SimilarNoteIds       NVARCHAR(200)  NULL,
        RequestPayload       NVARCHAR(MAX)  NOT NULL,
        ResponseRetCode      INT            NOT NULL,
        ResponsePayload      NVARCHAR(MAX)  NULL,
        SuggestedTriageFlag  NVARCHAR(20)   NULL,   -- Low | Medium | High | Critical (advisory)
        Summary              NVARCHAR(MAX)  NULL,
        CreatedAt            DATETIME2(3)   NOT NULL CONSTRAINT DF_AIAssist_CreatedAt DEFAULT SYSUTCDATETIME(),
        ProcessingTimeMs     INT            NOT NULL,
        CONSTRAINT PK_AIAssistanceLog PRIMARY KEY CLUSTERED (AssistanceId),
        CONSTRAINT FK_AIAssist_Encounter
            FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId)
    )
    /* Append-only ledger: INSERT-only, tamper-evident, ledger-digest verifiable.  */
    /* Adds GENERATED ALWAYS ledger_start_transaction_id / _sequence_number columns */
    /* plus a system ledger view. A regular table can't be converted to a ledger    */
    /* table, so fresh deploys must create it as a ledger table from the start.     */
    WITH (LEDGER = ON (APPEND_ONLY = ON));
    PRINT '  clinical.AIAssistanceLog created (append-only ledger).';
END
ELSE
    PRINT '  clinical.AIAssistanceLog already exists — skipping.';
GO

/* ---- The assistance procedure ------------------------------------------ */
PRINT '=== Creating clinical.GenerateClinicalAssistance ==='
GO

CREATE OR ALTER PROCEDURE clinical.GenerateClinicalAssistance
    @EncounterId     INT,
    @ModelDeployment NVARCHAR(64) = N'gpt-5',      -- Foundry reasoning-model deployment name
    @TopK            INT          = 5             -- similar historical notes to ground on
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @startTime DATETIME2 = SYSUTCDATETIME();

    /* -- 1. Live chart for this encounter -------------------------------- */
    DECLARE
        @PatientId    INT,
        @PatientName  NVARCHAR(200),
        @AgeYears     INT,
        @Sex          NVARCHAR(10),
        @EncType      NVARCHAR(20),
        @Diagnoses    NVARCHAR(MAX),
        @Medications  NVARCHAR(MAX),
        @Allergies    NVARCHAR(MAX),
        @LatestVitals NVARCHAR(MAX),
        @RecentLabs   NVARCHAR(MAX);

    SELECT
        @PatientId    = PatientId,
        @PatientName  = PatientName,
        @AgeYears     = AgeYears,
        @Sex          = Sex,
        @EncType      = EncounterType,
        @Diagnoses    = CONVERT(NVARCHAR(MAX), Diagnoses),
        @Medications  = CONVERT(NVARCHAR(MAX), Medications),
        @Allergies    = CONVERT(NVARCHAR(MAX), Allergies),
        @LatestVitals = CONVERT(NVARCHAR(MAX), LatestVitals),
        @RecentLabs   = CONVERT(NVARCHAR(MAX), RecentLabs)
    FROM clinical.vPatientChart
    WHERE EncounterId = @EncounterId;

    IF @PatientId IS NULL
    BEGIN
        RAISERROR('Encounter %d not found.', 16, 1, @EncounterId);
        RETURN;
    END

    /* -- 2. Build a case summary and retrieve similar notes (RAG) -------- */
    /* The most recent note on this encounter is the best seed for "find cases    */
    /* like this one"; fall back to the diagnosis list if there is no note yet.    */
    DECLARE @caseSummary NVARCHAR(MAX) =
        N'Encounter type ' + ISNULL(@EncType, N'?')
        + N'. Age ' + ISNULL(CAST(@AgeYears AS NVARCHAR(10)), N'?')
        + N', sex ' + ISNULL(@Sex, N'?')
        + N'. Diagnoses: ' + ISNULL(@Diagnoses, N'[]')
        + N'. Latest note: '
        + ISNULL((SELECT TOP (1) n.NoteText
                  FROM clinical.ClinicalNote AS n
                  JOIN clinical.Encounter    AS e ON e.EncounterId = n.EncounterId
                  WHERE e.EncounterId = @EncounterId
                  ORDER BY n.CreatedAt DESC), N'(none)');

    DECLARE @caseEmbedding VECTOR(3072, float16);
    SET @caseEmbedding = AI_GENERATE_EMBEDDINGS(@caseSummary USE MODEL WardGeneralEmbeddingModel);

    /* Similar historical notes from OTHER encounters (latest updateable DiskANN   */
    /* index): SELECT TOP (N) WITH APPROXIMATE + VECTOR_SEARCH, no TOP_N. The      */
    /* WHERE excludes this encounter DURING graph traversal (iterative filtering). */
    DECLARE @similar TABLE (
        NoteId       INT,
        EncounterId  INT,
        NoteType     NVARCHAR(20),
        NoteText     NVARCHAR(MAX),
        Distance     FLOAT
    );

    INSERT INTO @similar (NoteId, EncounterId, NoteType, NoteText, Distance)
    SELECT TOP (@TopK) WITH APPROXIMATE
        n.NoteId,
        n.EncounterId,
        n.NoteType,
        n.NoteText,
        vs.distance
    FROM VECTOR_SEARCH(
        TABLE      = clinical.ClinicalNoteEmbeddings AS emb,
        COLUMN     = Embedding,
        SIMILAR_TO = @caseEmbedding,
        METRIC     = 'cosine'
    ) AS vs
    JOIN clinical.ClinicalNote AS n ON n.NoteId = emb.NoteId
    WHERE n.EncounterId <> @EncounterId
    ORDER BY vs.distance;

    DECLARE @similarNoteIds NVARCHAR(200) =
        (SELECT STRING_AGG(CAST(NoteId AS NVARCHAR(20)), ',') FROM @similar);

    DECLARE @similarContext NVARCHAR(MAX) = N'';
    SELECT @similarContext = @similarContext
        + N'- (' + NoteType + N', similarity '
        + FORMAT(1.0 - Distance, 'N2') + N') '
        + LEFT(NoteText, 400) + CHAR(10)
    FROM @similar
    ORDER BY Distance;

    /* -- 3. Build the prompt -------------------------------------------- */
    /* Advisory framing: the engine ASSISTS, it does not decide. It offers a       */
    /* SUGGESTED triage flag for the attending to confirm/override, plus grounded  */
    /* considerations — never orders, never a diagnosis, never a prescription.     */
    DECLARE @prompt NVARCHAR(MAX) = N'You assist the attending physician at Ward General Hospital. You do NOT make
clinical decisions, you do NOT diagnose, and you do NOT prescribe. Review the
current chart and the similar historical cases, then help the attending by
offering (a) a SUGGESTED triage flag for them to confirm or override, and
(b) a short summary of considerations grounded in the chart and the cited
similar cases. Flag anything urgent. The attending is the decision-maker.

CURRENT CHART
- Encounter type: ' + ISNULL(@EncType, N'?') + N'
- Age/Sex: ' + ISNULL(CAST(@AgeYears AS NVARCHAR(10)), N'?') + N' / ' + ISNULL(@Sex, N'?') + N'
- Active diagnoses: ' + ISNULL(@Diagnoses, N'[]') + N'
- Medications: ' + ISNULL(@Medications, N'[]') + N'
- Allergies: ' + ISNULL(@Allergies, N'[]') + N'
- Latest vitals: ' + ISNULL(@LatestVitals, N'[]') + N'
- Recent labs: ' + ISNULL(@RecentLabs, N'[]') + N'

SIMILAR HISTORICAL CASES (retrieved by vector similarity on clinical notes)
' + ISNULL(NULLIF(@similarContext, N''), N'(no comparable prior notes found)') + N'

Respond with ONLY a JSON object. "triage_flag" MUST be exactly one word — one of Low, Medium, High, or Critical (nothing else; the app labels it as "suggested" and the attending confirms):
{"triage_flag": "<Low|Medium|High|Critical>", "summary": "<3-5 sentence considerations for the attending, referencing the vitals/labs and any relevant similar case>"}';

    /* -- 4. Call the Foundry reasoning-model deployment ------------------ */
    /* gpt-5 is a REASONING model: it uses max_completion_tokens (not max_tokens) */
    /* and rejects temperature/top_p. reasoning_effort tunes thinking depth and   */
    /* verbosity tunes answer length — both set to 'low' here for snappy, more    */
    /* consistent demo latency (a triage flag + short summary doesn't need deep   */
    /* reasoning). Budget the completion generously: hidden reasoning tokens draw  */
    /* from the same pool.                                                         */
    /* Quote the escaped prompt INLINE. STRING_ESCAPE emits the body WITHOUT the   */
    /* surrounding quotes, so wrap it here with "...". Do NOT add the quotes with a */
    /* post-hoc REPLACE over @payload: REPLACE on nvarchar(max) raised "String or   */
    /* binary data would be truncated" on real charts (~5 KB payloads).            */
    DECLARE @payload NVARCHAR(MAX) = N'{
        "messages": [
            {"role": "system", "content": "You are a clinical decision-SUPPORT engine that assists a physician; you never make the final decision. Always respond with valid JSON only."},
            {"role": "user", "content": "' + STRING_ESCAPE(@prompt, 'json') + N'"}
        ],
        "max_completion_tokens": 2000,
        "reasoning_effort": "low",
        "verbosity": "low"
    }';

    DECLARE @chatUrl NVARCHAR(500) =
        N'https://collierhealth-ai.openai.azure.com/openai/deployments/'
        + @ModelDeployment
        + N'/chat/completions?api-version=2025-04-01-preview';

    DECLARE @response NVARCHAR(MAX);
    DECLARE @retval   INT = -1;

    /* -- 5. Parse the answer -------------------------------------------- */
    DECLARE @triageFlag NVARCHAR(20), @summary NVARCHAR(MAX), @content NVARCHAR(MAX);

    /* sp_invoke_external_rest_endpoint parses the HTTP response BODY as JSON and    */
    /* RAISES (Msg 13609 "JSON text is not properly formatted") when the body isn't  */
    /* JSON — e.g. a gateway/error page, a timeout, or a content-filter block. That  */
    /* would abort the proc and surface a raw error to the app. Wrap the call +      */
    /* parse so any failure degrades to a graceful, audited fallback instead.        */
    BEGIN TRY
        EXEC @retval = sp_invoke_external_rest_endpoint
            @url        = @chatUrl,
            @method     = 'POST',
            @credential = [https://collierhealth-ai.openai.azure.com/],
            @payload    = @payload,
            @timeout    = 120,
            @response   = @response OUTPUT;

        IF @retval = 0
        BEGIN
            SET @content = JSON_VALUE(@response, '$.result.choices[0].message.content');

            /* Some models fence JSON in ```json ... ``` — strip it. */
            IF @content LIKE '%```json%'
            BEGIN
                SET @content = SUBSTRING(@content, CHARINDEX('```json', @content) + 7, LEN(@content));
                SET @content = SUBSTRING(@content, 1, CHARINDEX('```', @content) - 1);
            END
            SET @content = LTRIM(RTRIM(@content));

            SET @triageFlag = JSON_VALUE(@content, '$.triage_flag');
            SET @summary    = JSON_VALUE(@content, '$.summary');
        END

        IF @summary IS NULL
        BEGIN
            SET @triageFlag = N'Medium';
            SET @summary    = CASE WHEN @retval = 0
                THEN N'AI returned a response but JSON parsing failed. Raw: '
                     + LEFT(ISNULL(@content, ISNULL(@response, N'NULL')), 400)
                ELSE N'AI assistance unavailable (endpoint returned code '
                     + CAST(@retval AS NVARCHAR(10)) + N'). Response: '
                     + LEFT(ISNULL(@response, N'NULL'), 400) END;
        END
    END TRY
    BEGIN CATCH
        SET @retval     = -1;
        SET @triageFlag = N'Medium';
        SET @summary    = N'AI assistance unavailable — the model call failed ('
                          + LEFT(ERROR_MESSAGE(), 300) + N'). Verify manually.';
    END CATCH

    /* -- 6. Audit -------------------------------------------------------- */
    INSERT INTO clinical.AIAssistanceLog (
        EncounterId, PatientId, ModelDeployment, SimilarNoteIds,
        RequestPayload, ResponseRetCode, ResponsePayload,
        SuggestedTriageFlag, Summary, ProcessingTimeMs
    )
    VALUES (
        @EncounterId, @PatientId, @ModelDeployment, @similarNoteIds,
        @payload, @retval, LEFT(@response, 4000),
        @triageFlag, @summary,
        DATEDIFF(MILLISECOND, @startTime, SYSUTCDATETIME())
    );

    /* -- 7. Return the assistance (advisory — the attending decides) ----- */
    SELECT
        @EncounterId                                   AS EncounterId,
        @PatientName                                   AS PatientName,
        @triageFlag                                    AS SuggestedTriageFlag,
        @summary                                       AS Summary,
        @similarNoteIds                                AS GroundedOnNoteIds,
        DATEDIFF(MILLISECOND, @startTime, SYSUTCDATETIME()) AS ProcessingTimeMs;
END;
GO

PRINT '  clinical.GenerateClinicalAssistance created.'
GO
