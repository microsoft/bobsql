/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   08-ai-assistance.sql : AI layer 3 of 3 — clinical assistance proc
   Run order            : after 07-vector-index.sql

   clinical.GenerateClinicalAssistance stitches the whole in-engine AI story
   into one call the app / DAB / MCP can invoke:

     1. Pull the live chart for an encounter (clinical.vPatientChart)
     2. Embed a short "case summary" of that chart and run VECTOR_SEARCH over
        clinical.ClinicalNoteEmbeddings to find the most semantically similar
        historical notes (retrieval-augmented generation — RAG, in the engine)
     3. Send chart + similar-case context to the Collier Health Foundry chat
        deployment via sp_invoke_external_rest_endpoint — routed through the
        Azure API Management AI gateway, so every model call is rate-limited,
        metered, and content-filtered on the way out
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

   GOVERNED BY DEFAULT:
     The chat call goes through the API Management AI gateway (@UseGateway = 1),
     because that is how you would run it in a hospital: token rate limiting for
     cost control, token metrics in Azure Monitor for observability (Observability),
     content safety and jailbreak detection on the prompt and the answer. The
     toggle exists so you can prove the gateway costs you nothing in the query —
     @UseGateway = 0 calls Foundry directly with the SAME payload and returns the
     SAME result set. Governance did not cost a rewrite; it cost a URL.

     Note the asymmetry, and that it is deliberate: EMBEDDINGS still go straight
     to Foundry (AI_GENERATE_EMBEDDINGS, on the primary and on the research
     replica). Only the CHAT completion is routed through the gateway.

     Auth is passwordless end to end — no key anywhere:
       DB  --managed identity-->  APIM  --managed identity-->  gpt-5
     The database reaches APIM with its OWN managed-identity Entra token, on the
     first-party Cognitive Services audience — the SAME token the direct Foundry
     path uses. APIM validates it (validate-azure-ad-token) and then reaches
     Azure OpenAI with its own identity. No app registration, nothing to leak.

   PREREQUISITES:
     * 06-ai-embeddings.sql and 07-vector-index.sql already run (external model,
       embeddings, index).
     * A Foundry chat/reasoning deployment (e.g. gpt-5) on the SAME Foundry
       resource, reusing the credential created in 06 (managed identity, passwordless).
     * The gateway provisioned — deploy-ai.ps1 does this for you unless you
       passed -NoGateway.

   BEFORE YOU RUN — replace two placeholders:
     <your-foundry>  ->  your Microsoft Foundry (Azure OpenAI) resource name,
                         the SAME value you replaced in 06
     <your-apim>     ->  your API Management service name

   DEPLOYED WITH -NoGateway?
     You have no gateway to call, so make direct the default: change @UseGateway's
     default below from 1 to 0. (The credential block is harmless either way —
     it validates nothing at create time.) If you add the gateway later, put the
     default back to 1 and re-run this script -- it is CREATE OR ALTER, so that
     is the whole of it.

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

/* Stop before doing damage if the find-and-replace above has not been done.

   The patterns bracket the angle characters — [<]your-foundry[>] — so that your
   find-and-replace rewrites the literal being tested but NOT the pattern testing
   it. Replace both sides and the comparison reduces to "does this URL contain
   the name in this URL", which is true for every possible name, so the guard
   fires forever.

   And it sets NOEXEC rather than throwing, because THROW ends only its own
   batch — every batch after the next GO still runs. Under NOEXEC the rest of the
   file compiles and does nothing. The last line of this file turns it off. */
IF 'https://<your-foundry>.openai.azure.com/' LIKE '%[<]your-foundry[>]%'
   OR 'https://<your-apim>.azure-api.net/' LIKE '%[<]your-apim[>]%'
BEGIN
    RAISERROR('Replace <your-foundry> and <your-apim> throughout this file before running it. See the BEFORE YOU RUN block above. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---- Gateway credential (DB -> APIM, via the server's managed identity) ---- */
/* Managed-identity DBSC: the wardgeneral server's system-assigned identity mints  */
/* an Entra token for the audience named in SECRET and sends it as a Bearer header  */
/* — no key. Same pattern 06 uses for Foundry. The credential is bound BY NAME to   */
/* the URL prefix of the call, so the gateway host needs its own credential even     */
/* though the audience is identical. Skip this if you deployed with -NoGateway.      */
IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials
               WHERE name = 'https://<your-apim>.azure-api.net/')
BEGIN
    CREATE DATABASE SCOPED CREDENTIAL [https://<your-apim>.azure-api.net/]
    WITH IDENTITY = 'Managed Identity',
         SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}';   -- first-party audience; the SAME token the direct Foundry path uses (06). No app registration.

    PRINT '  Gateway credential created (managed identity — no key).';
END
ELSE
    PRINT '  Gateway credential already exists — left alone.';
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
        /* The DEFAULT is deliberately UNNAMED. Dropping a ledger table only soft-     */
        /* deletes it: the engine renames it to MSSQL_DroppedLedgerTable_<name>_<guid> */
        /* and keeps it physically so ledger verification still works — and the        */
        /* retention table KEEPS any explicitly named default constraint. Constraint   */
        /* names are unique database-wide, so a named default here could never be      */
        /* created again after a single drop, and this script would be un-re-runnable. */
        /* Letting the engine generate the name keeps the deploy idempotent.           */
        CreatedAt            DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
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
    @TopK            INT          = 5,            -- similar historical notes to ground on
    @UseGateway      BIT          = 1             -- 1 = via the APIM AI gateway, 0 = direct to gpt-5
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

    /* Two routes to the same model. Identical payload, identical response shape —   */
    /* the only difference is the host and the credential. Everything the gateway     */
    /* adds (token rate limiting, token metrics, content safety, jailbreak detection) */
    /* happens in between, and the query never learns about it.                       */
    DECLARE @gatewayUrl NVARCHAR(500) =
        N'https://<your-apim>.azure-api.net/openai/deployments/'
        + @ModelDeployment
        + N'/chat/completions?api-version=2025-04-01-preview';

    DECLARE @directUrl NVARCHAR(500) =
        N'https://<your-foundry>.openai.azure.com/openai/deployments/'
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
        IF @UseGateway = 1
            /* DB -> APIM (server managed identity) -> gpt-5 (APIM managed identity). */
            EXEC @retval = sp_invoke_external_rest_endpoint
                @url        = @gatewayUrl,
                @method     = 'POST',
                @credential = [https://<your-apim>.azure-api.net/],
                @payload    = @payload,
                @timeout    = 120,
                @response   = @response OUTPUT;
        ELSE
            /* DB -> gpt-5 directly (server managed identity). */
            EXEC @retval = sp_invoke_external_rest_endpoint
                @url        = @directUrl,
                @method     = 'POST',
                @credential = [https://<your-foundry>.openai.azure.com/],
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
        @EncounterId, @PatientId,
        /* Stamp the route into the audit row: a reviewer can tell a governed call
           from a direct one months later, without guessing. */
        @ModelDeployment + CASE WHEN @UseGateway = 1 THEN N' (via gateway)' ELSE N' (direct)' END,
        @similarNoteIds,
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
        CASE WHEN @UseGateway = 1 THEN N'APIM gateway' ELSE N'direct' END AS Path,
        DATEDIFF(MILLISECOND, @startTime, SYSUTCDATETIME()) AS ProcessingTimeMs;
END;
GO

PRINT '  clinical.GenerateClinicalAssistance created (@UseGateway defaults to 1 — calls go through the gateway).'
GO

/* Clear the placeholder guard, whether or not it fired, so the session is left
   executing normally. If the only output you saw was the guard's error, nothing
   above this line ran. */
SET NOEXEC OFF;
GO
