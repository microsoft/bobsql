/* =======================================================================
   Zava Hospital – Clinical Recommendation via NIM Chat
   SQL Server 2025 + NVIDIA NIM on AKS

   Flow:
     1. Vector search finds similar past encounters (embeddings → NIM)
     2. Gather current patient vitals, symptoms, allergies, orders
     3. Send context + similar cases to NIM chat (llama-3.2-3b-instruct)
     4. Return structured JSON recommendation

   Endpoint: https://nim-aks.local/v1/chat/completions
   Model:    meta/llama-3.2-3b-instruct
   ======================================================================= */
USE zavahospital;
GO

CREATE OR ALTER PROCEDURE clinical.usp_clinical_recommendation
(
    @PatientID     INT,
    @Prompt        NVARCHAR(4000),        -- clinician's question / concern
    @SearchTopN    INT            = 5,    -- similar cases to retrieve
    @MaxDistance    FLOAT          = 0.45, -- cosine distance threshold
    @MaxTokens     INT            = 1024,
    @Temperature   FLOAT          = 0.3
)
AS
BEGIN
    SET NOCOUNT ON;

    /* ==========================================================
       STEP 1: Gather current patient context
    ========================================================== */

    -- Patient demographics + allergies
    DECLARE @FirstName    NVARCHAR(100),
            @LastName     NVARCHAR(100),
            @DOB          DATE,
            @Gender       NVARCHAR(20),
            @Allergies    NVARCHAR(500),
            @EncounterID  BIGINT,
            @Reason       NVARCHAR(200);

    SELECT @FirstName   = FirstName,
           @LastName    = LastName,
           @DOB         = DOB,
           @Gender      = Gender,
           @Allergies   = Allergies
    FROM core.Patients
    WHERE PatientID = @PatientID;

    IF @FirstName IS NULL
    BEGIN
        RAISERROR('Patient %d not found.', 16, 1, @PatientID);
        RETURN;
    END

    -- Current open encounter
    SELECT TOP (1) @EncounterID = EncounterID, @Reason = Reason
    FROM core.Encounters
    WHERE PatientID = @PatientID AND DischargeDate IS NULL
    ORDER BY AdmitDate DESC;

    IF @EncounterID IS NULL
    BEGIN
        RAISERROR('No open encounter for patient %d.', 16, 1, @PatientID);
        RETURN;
    END

    -- Latest vitals
    DECLARE @vitals_text NVARCHAR(MAX);
    SELECT TOP (1) @vitals_text = CONCAT(
        'HR:', HeartRate, ' BP:', BloodPressure,
        ' SpO2:', SpO2, ' Temp:', TemperatureC, '°C',
        ' RR:', RespiratoryRate
    )
    FROM clinical.VitalsSnapshots
    WHERE EncounterID = @EncounterID
    ORDER BY RecordedAt DESC;

    -- Current symptoms
    DECLARE @symptoms_text NVARCHAR(MAX);
    SELECT @symptoms_text = STRING_AGG(Description, ', ')
    FROM clinical.Symptoms
    WHERE EncounterID = @EncounterID;

    -- Active orders
    DECLARE @orders_text NVARCHAR(MAX);
    SELECT @orders_text = STRING_AGG(
        CONCAT(OrderTypeCode, ': ', LEFT(Details, 200)),
        '; '
    )
    FROM clinical.Orders
    WHERE EncounterID = @EncounterID AND Status IN (N'Pending', N'InProgress');

    /* ==========================================================
       STEP 2: Vector search for similar past encounters
    ========================================================== */
    DECLARE @q VECTOR(1024) = AI_GENERATE_EMBEDDINGS(
        @Prompt
        USE MODEL NIMEmbeddingModel
    );

    DECLARE @FetchN INT = @SearchTopN * 3;

    DECLARE @similar_cases NVARCHAR(MAX);

    SELECT @similar_cases = STRING_AGG(
        CONCAT(
            'Case(dist=', FORMAT(matched.distance, 'N3'), '): ',
            'Reason:', e.Reason,
            ' Symptoms:', s.Description,
            ' Vitals: HR:', v.HeartRate, ' BP:', v.BloodPressure,
            ' Note:', LEFT(dn.NoteText, 300)
        ),
        CHAR(10)
    )
    FROM (
        SELECT TOP (@SearchTopN)
            ev.EncounterID,
            ev.PatientID,
            r.distance
        FROM VECTOR_SEARCH(
                TABLE      = clinical.EncounterVectors AS ev,
                COLUMN     = NarrativeEmbedding,
                SIMILAR_TO = @q,
                METRIC     = N'cosine',
                TOP_N      = @FetchN
            ) AS r
        WHERE r.distance <= @MaxDistance
          AND ev.EncounterID <> @EncounterID  -- exclude current encounter
        ORDER BY r.distance ASC
    ) AS matched
    JOIN core.Encounters e       ON e.EncounterID = matched.EncounterID
    OUTER APPLY (
        SELECT TOP (1) Description FROM clinical.Symptoms
        WHERE EncounterID = matched.EncounterID
    ) s
    OUTER APPLY (
        SELECT TOP (1) HeartRate, BloodPressure FROM clinical.VitalsSnapshots
        WHERE EncounterID = matched.EncounterID ORDER BY RecordedAt DESC
    ) v
    OUTER APPLY (
        SELECT TOP (1) NoteText FROM clinical.DoctorNotes
        WHERE EncounterID = matched.EncounterID ORDER BY CreatedAt DESC
    ) dn;

    /* ==========================================================
       STEP 3: Build chat prompts
    ========================================================== */
    DECLARE @system_prompt NVARCHAR(MAX) =
N'You are a clinical decision support assistant at Zava Hospital. Draft a provisional recommendation for clinician review.
Rules:
1) Name specific drugs with doses and routes (e.g. nicardipine 5 mg/h IV, acetaminophen 1000 mg PO).
2) Check patient allergies and flag contraindications.
3) Include measurable targets when relevant (e.g. reduce MAP ≤25% in first hour).
4) Address all abnormal vitals.
5) Address symptom relief.
6) Reference similar past cases when relevant.
Use only provided context. Return STRICT JSON matching the schema, no extra prose.';

    DECLARE @user_prompt NVARCHAR(MAX) = CONCAT(
        N'Patient: ', @FirstName, N' ', @LastName,
        N', DOB:', CONVERT(NVARCHAR(10), @DOB, 120),
        N', Gender:', @Gender,
        N', Allergies:', ISNULL(@Allergies, N'None known'), CHAR(10),
        N'Encounter reason: ', ISNULL(@Reason, N'Unknown'), CHAR(10),
        N'Current vitals: ', ISNULL(@vitals_text, N'Not recorded'), CHAR(10),
        N'Current symptoms: ', ISNULL(@symptoms_text, N'None recorded'), CHAR(10),
        N'Active orders: ', ISNULL(@orders_text, N'None'), CHAR(10),
        N'Clinician question: ', @Prompt, CHAR(10),
        N'Similar past cases:', CHAR(10), ISNULL(@similar_cases, N'None found'), CHAR(10),
        N'Return JSON: {"recommendation":{"assessment":[string],"contraindications":[string],"medications":[{"name":string,"dose":string,"route":string}],"monitoring":[string],"follow_up":string}}'
    );

    /* ==========================================================
       STEP 4: Call NIM chat via sp_invoke_external_rest_endpoint
    ========================================================== */
    DECLARE @url NVARCHAR(4000) = N'https://nim-aks.local/v1/chat/completions';

    DECLARE @payload NVARCHAR(MAX) = JSON_OBJECT(
        'model':       'meta/llama-3.2-3b-instruct',
        'messages':    JSON_ARRAY(
                         JSON_OBJECT('role':'system', 'content':@system_prompt),
                         JSON_OBJECT('role':'user',   'content':@user_prompt)
                       ),
        'max_tokens':  @MaxTokens,
        'temperature': @Temperature
    );

    DECLARE @response NVARCHAR(MAX);
    DECLARE @rc INT;

    EXEC @rc = sp_invoke_external_rest_endpoint
        @url      = @url,
        @method   = 'POST',
        @payload  = @payload,
        @timeout  = 120,
        @response = @response OUTPUT;

    /* ==========================================================
       STEP 5: Parse and return results
    ========================================================== */
    DECLARE @http_code INT = TRY_CONVERT(INT,
        JSON_VALUE(@response, '$.response.status.http.code'));

    -- Extract assistant message (use OPENJSON to avoid 4K truncation)
    DECLARE @assistant_txt NVARCHAR(MAX);
    SELECT @assistant_txt = content
    FROM OPENJSON(@response, '$.result')
    WITH (content NVARCHAR(MAX) '$.choices[0].message.content');

    -- Strip markdown fences if present
    IF @assistant_txt LIKE '%```%'
    BEGIN
        SET @assistant_txt = REPLACE(@assistant_txt, '```json', '');
        SET @assistant_txt = REPLACE(@assistant_txt, '```', '');
    END

    -- Return recommendation + context
    SELECT
        @PatientID                                    AS PatientID,
        CONCAT(@FirstName, N' ', @LastName)           AS PatientName,
        @Allergies                                    AS Allergies,
        @Reason                                       AS EncounterReason,
        @vitals_text                                  AS LatestVitals,
        @symptoms_text                                AS CurrentSymptoms,
        @http_code                                    AS HttpStatus,
        LTRIM(RTRIM(@assistant_txt))                  AS Recommendation;
END
GO
