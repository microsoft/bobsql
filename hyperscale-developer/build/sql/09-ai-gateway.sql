/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   09-ai-gateway.sql : OPTIONAL — route the clinical assistance call through the
                       Azure API Management AI Gateway instead of calling gpt-5
                       directly.
   Run order         : after 07-ai-assistance.sql, once setup-ai-gateway.ps1
                       has finished provisioning the gateway.

   Mirrors the zavalending demo3 "10-ai-gateway-switch.sql" idea: the proc's
   LOGIC does not change — we only swap the URL + credential it calls. Same
   stored-proc call, same result set, but now every AI interaction is governed:

     - Token rate limiting (10K TPM)          -> cost control
     - Token metrics (Azure Monitor)          -> observability
     - Managed-identity auth (APIM -> gpt-5)  -> no Azure OpenAI key surface
     - Content safety + jailbreak (optional, add-content-safety.ps1)

   Auth model (fully passwordless — no key anywhere):
     DB  --managed identity (Entra token)-->  APIM  --managed identity-->  gpt-5
     The database reaches APIM with its OWN managed-identity Entra token (a
     Managed Identity database-scoped credential — the same pattern 06/07 use for
     Foundry). APIM validates that token (validate-azure-ad-token, authorizing the
     wardgeneral server's managed identity) and then reaches Azure OpenAI with its
     OWN managed identity. No subscription key, no Azure OpenAI key — nothing to leak.

   BEFORE RUNNING:
     Run deploy\setup-ai-gateway.ps1 once — it configures the gateway to accept the
     database's managed-identity token on the first-party Cognitive Services audience.
     Nothing to paste: the credential below already uses that audience — the SAME token
     the direct Foundry path uses in 06/07.

   Toggle at call time:
     EXEC clinical.GenerateClinicalAssistance @EncounterId = 1001;                 -- via gateway (default)
     EXEC clinical.GenerateClinicalAssistance @EncounterId = 1001, @UseGateway = 0; -- straight to gpt-5

   All data is synthetic. No real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- 1. Gateway credential (DB -> APIM, via the server's managed identity) ---- */
/* Managed-identity DBSC: the wardgeneral server's system-assigned identity mints  */
/* an Entra token for the gateway's audience (resourceid) and sends it as a Bearer  */
/* header — no key. Same pattern 06/07 use for Foundry. The credential NAME must be */
/* the gateway host (more generic than the request URL used in the proc below).     */
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials
           WHERE name = 'https://collierhealth-ai-gateway.azure-api.net/')
    DROP DATABASE SCOPED CREDENTIAL [https://collierhealth-ai-gateway.azure-api.net/];
GO

CREATE DATABASE SCOPED CREDENTIAL [https://collierhealth-ai-gateway.azure-api.net/]
WITH IDENTITY = 'Managed Identity',
     SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}';   -- first-party audience; the SAME token the direct Foundry path uses (06/07). No app registration.
GO
PRINT '  Gateway credential created (managed identity — no key).';
GO

/* ---- 2. Same proc, gateway-aware ---------------------------------------- */
/* Only additions vs 07: the @UseGateway toggle and the branched sp_invoke     */
/* call (gateway URL + gateway credential, or the direct URL + direct           */
/* credential). Everything else — chart read, RAG, advisory framing, parsing,   */
/* audit — is byte-for-byte the 07 procedure.                                   */
PRINT '=== Re-creating clinical.GenerateClinicalAssistance (gateway-aware) ==='
GO

CREATE OR ALTER PROCEDURE clinical.GenerateClinicalAssistance
    @EncounterId     INT,
    @ModelDeployment NVARCHAR(64) = N'gpt-5',
    @TopK            INT          = 5,
    @UseGateway      BIT          = 1          -- 1 = via APIM gateway, 0 = direct to gpt-5
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

    /* -- 3. Build the prompt (advisory framing — the engine ASSISTS) ----- */
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

    /* -- 4. Call gpt-5 — via the gateway or directly -------------------- */
    /* Quote the escaped prompt INLINE (STRING_ESCAPE omits the surrounding         */
    /* quotes). Do NOT add them with a post-hoc REPLACE over @payload: REPLACE on    */
    /* nvarchar(max) raised "String or binary data would be truncated" on real       */
    /* charts (~5 KB payloads).                                                     */
    DECLARE @payload NVARCHAR(MAX) = N'{
        "messages": [
            {"role": "system", "content": "You are a clinical decision-SUPPORT engine that assists a physician; you never make the final decision. Always respond with valid JSON only."},
            {"role": "user", "content": "' + STRING_ESCAPE(@prompt, 'json') + N'"}
        ],
        "max_completion_tokens": 2000,
        "reasoning_effort": "low",
        "verbosity": "low"
    }';

    DECLARE @response NVARCHAR(MAX);
    DECLARE @retval   INT;

    IF @UseGateway = 1
    BEGIN
        /* DB -> APIM (server managed identity) -> gpt-5 (APIM managed identity). */
        DECLARE @gatewayUrl NVARCHAR(500) =
            N'https://collierhealth-ai-gateway.azure-api.net/openai/deployments/'
            + @ModelDeployment
            + N'/chat/completions?api-version=2025-04-01-preview';

        EXEC @retval = sp_invoke_external_rest_endpoint
            @url        = @gatewayUrl,
            @method     = 'POST',
            @credential = [https://collierhealth-ai-gateway.azure-api.net/],
            @payload    = @payload,
            @timeout    = 120,
            @response   = @response OUTPUT;
    END
    ELSE
    BEGIN
        /* DB -> gpt-5 directly (server managed identity). */
        DECLARE @directUrl NVARCHAR(500) =
            N'https://collierhealth-ai.openai.azure.com/openai/deployments/'
            + @ModelDeployment
            + N'/chat/completions?api-version=2025-04-01-preview';

        EXEC @retval = sp_invoke_external_rest_endpoint
            @url        = @directUrl,
            @method     = 'POST',
            @credential = [https://collierhealth-ai.openai.azure.com/],
            @payload    = @payload,
            @timeout    = 120,
            @response   = @response OUTPUT;
    END

    /* -- 5. Parse the answer -------------------------------------------- */
    DECLARE @triageFlag NVARCHAR(20), @summary NVARCHAR(MAX);

    IF @retval = 0
    BEGIN
        DECLARE @content NVARCHAR(MAX) =
            JSON_VALUE(@response, '$.result.choices[0].message.content');

        IF @content LIKE '%```json%'
        BEGIN
            SET @content = SUBSTRING(@content, CHARINDEX('```json', @content) + 7, LEN(@content));
            SET @content = SUBSTRING(@content, 1, CHARINDEX('```', @content) - 1);
        END
        SET @content = LTRIM(RTRIM(@content));

        SET @triageFlag = JSON_VALUE(@content, '$.triage_flag');
        SET @summary    = JSON_VALUE(@content, '$.summary');

        IF @summary IS NULL
        BEGIN
            SET @triageFlag = N'Medium';
            SET @summary    = N'AI returned a response but JSON parsing failed. Raw: '
                              + LEFT(ISNULL(@content, N'NULL'), 400);
        END
    END
    ELSE
    BEGIN
        SET @triageFlag = N'Medium';
        SET @summary    = N'AI assistance unavailable (endpoint returned code '
                          + CAST(@retval AS NVARCHAR(10)) + N'). Response: '
                          + LEFT(ISNULL(@response, N'NULL'), 400);
    END

    /* -- 6. Audit -------------------------------------------------------- */
    INSERT INTO clinical.AIAssistanceLog (
        EncounterId, PatientId, ModelDeployment, SimilarNoteIds,
        RequestPayload, ResponseRetCode, ResponsePayload,
        SuggestedTriageFlag, Summary, ProcessingTimeMs
    )
    VALUES (
        @EncounterId, @PatientId,
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

PRINT '  clinical.GenerateClinicalAssistance is now gateway-aware (@UseGateway defaults to 1).'
GO
