uSE [zavacliniq];
GO
CREATE OR ALTER PROCEDURE care.usp_ai_agent_care_plan
  @prompt         NVARCHAR(MAX),   -- free text query from user
  @patient_json   JSON,            -- patient context as native JSON
  @patient_id     NVARCHAR(64),    -- patient identifier for ledger
  @topk           INT = 5,
  @raw_response   JSON OUTPUT,     -- REST wrapper as JSON (native)
  @careplan_json  JSON OUTPUT      -- extracted care plan (native)
AS
BEGIN
  SET NOCOUNT ON;

    /* ============================================================
     STEP 0: Normalize patient JSON (keep as native JSON)
  ============================================================ */
  IF @patient_json IS NULL
      SET @patient_json = TRY_CAST(N'{}' AS JSON);

  /* ============================================================
     STEP 1: VECTOR SEARCH (kept as-is; returns text evidence)
  ============================================================ */
  IF OBJECT_ID('tempdb..#search_out') IS NOT NULL DROP TABLE #search_out;
  CREATE TABLE #search_out
  (
    Title     NVARCHAR(400),
    DocType   NVARCHAR(50),
    ChunkText NVARCHAR(MAX),
    distance  FLOAT
  );

  INSERT INTO #search_out (Title, DocType, ChunkText, distance)
  EXEC content.SearchChunksByPrompt_Vector
       @Prompt = @prompt,
       @TopK   = @topk;

  IF OBJECT_ID('tempdb..#rag_topk') IS NOT NULL DROP TABLE #rag_topk;
  CREATE TABLE #rag_topk
  (
    Title     NVARCHAR(400),
    DocType   NVARCHAR(50),
    ChunkText NVARCHAR(MAX),
    Score     FLOAT
  );

  INSERT INTO #rag_topk (Title, DocType, ChunkText, Score)
  SELECT TOP (@topk)
         Title, DocType, ChunkText, distance
  FROM #search_out
  ORDER BY distance ASC;

  /* ============================================================
     STEP 2: Build prompts (convert JSON -> NVARCHAR for display)
  ============================================================ */
  DECLARE @patient_json_text NVARCHAR(MAX) =
    CONVERT(NVARCHAR(MAX), JSON_QUERY(@patient_json, '$'));  -- canonical textual JSON

  DECLARE @evidence NVARCHAR(MAX) =
  (
    SELECT STRING_AGG(
             CONCAT('• [', ISNULL(DocType,'?'), '] ', Title, ': ', LEFT(ChunkText, 1000)),
             CHAR(10)
           ) WITHIN GROUP (ORDER BY Score)
    FROM #rag_topk
  );

  DECLARE @system_prompt NVARCHAR(MAX) =
N'You are a clinical assistant drafting a **provisional** outpatient care plan for clinician review.
Use only the provided patient context and evidence; do not invent facts. If uncertain, state assumptions.
Adjust recommendations for age, weight (weight-based dosing), vitals, allergies, comorbidities, renal/hepatic function, and pregnancy if provided.
Return STRICT JSON that matches the schema exactly, with no extra prose. This is not medical advice.';

  DECLARE @user_prompt NVARCHAR(MAX) =
    CONCAT(
      N'Patient input (free text):', CHAR(10), ISNULL(@prompt, N''), CHAR(10), CHAR(10),
      N'Patient context (JSON):',    CHAR(10), ISNULL(@patient_json_text, N'{}'), CHAR(10), CHAR(10),
      N'Evidence (top K chunks):',   CHAR(10), ISNULL(@evidence, N'[no evidence]'), CHAR(10), CHAR(10),
      N'Task:', CHAR(10),
      N'Draft a provisional care plan using this JSON schema (return ONLY JSON):', CHAR(10),
      N'{',
      N'  "care_plan": {',
      N'    "assessment": [ {"problem": "string", "supporting_evidence": ["string"] } ],',
      N'    "immediate_actions": ["string"],',
      N'    "diagnostics": ["string"],',
      N'    "medications": [ {"name":"string","dose":"string","route":"string","frequency":"string","notes":"string"} ],',
      N'    "nonpharmacologic": ["string"],',
      N'    "monitoring": ["string"],',
      N'    "patient_education": ["string"],',
      N'    "follow_up": {"timeline":"string","criteria_to_escalate":["string"]},',
      N'    "references": ["string"]',
      N'  }',
      N'}'
    );

  /* ============================================================
     STEP 3: Build REST payload with JSON_OBJECT/JSON_ARRAY
              (returns NVARCHAR payload; no manual escaping)
  ============================================================ */
 DECLARE @MODEL NVARCHAR(200)            = N'gpt-oss';
 DECLARE @payload NVARCHAR(MAX) =
    JSON_OBJECT(
      'model':    @MODEL,
      'messages': JSON_ARRAY(
                    JSON_OBJECT('role':'system','content':@system_prompt),
                    JSON_OBJECT('role':'user',  'content':@user_prompt)
                  ),
      'format':   'json',
      'stream':   CAST(0 AS bit)
    );

  DECLARE @headers NVARCHAR(MAX) = N'{"Content-Type":"application/json","Accept":"application/json"}';

  /* ============================================================
     STEP 4: Call Ollama; parse wrapper and extract care_plan
       NOTE: Use OPENJSON WITH NVARCHAR(MAX) (NOT JSON_VALUE)
             to avoid 4k truncation of long strings.
  ============================================================ */

  DECLARE @OLLAMA_CHAT_URL NVARCHAR(4000) = N'https://localhost/api/chat';  -- HTTPS reverse proxy
  DECLARE @timeout_seconds INT            = 180;
  DECLARE @resp NVARCHAR(MAX);
  DECLARE @rc INT;

  EXEC @rc = sys.sp_invoke_external_rest_endpoint
      @url      = @OLLAMA_CHAT_URL,
      @method   = 'POST',
      @headers  = @headers,
      @payload  = @payload,
      @timeout  = @timeout_seconds,
      @response = @resp OUTPUT;

  -- Promote wrapper to native JSON
  SET @raw_response = TRY_CAST(@resp AS JSON);

  -- HTTP code (short scalar -> JSON_VALUE ok)
  DECLARE @http_code INT =
    TRY_CONVERT(INT, JSON_VALUE(@raw_response, '$.response.status.http.code'));

  -- Extract result body as text
  DECLARE @body_text NVARCHAR(MAX) =
    CONVERT(NVARCHAR(MAX), JSON_QUERY(@raw_response, '$.result'));

  -- Extract the LONG message.content safely (no 4k cap)
  DECLARE @assistant_txt NVARCHAR(MAX);

  SELECT @assistant_txt = content
  FROM OPENJSON(@body_text)
  WITH (content NVARCHAR(MAX) '$.message.content');  -- << key fix

  -- Strip markdown fences if present
  IF @assistant_txt LIKE '%```%'
  BEGIN
    SET @assistant_txt = REPLACE(@assistant_txt, '```json', '');
    SET @assistant_txt = REPLACE(@assistant_txt, '```', '');
  END

  -- Parse the care_plan object into native JSON (NULL if not found/invalid)
  SET @careplan_json = TRY_CAST(JSON_QUERY(@assistant_txt, '$.care_plan') AS JSON);

  /* ============================================================
     STEP 5: Persist to NVARCHAR-based ledger (explicit converts)
  ============================================================ */
  DECLARE @evidence_json_text NVARCHAR(MAX) =
  (
    SELECT
      Title,
      DocType,
      Score,
      ChunkPreview = LEFT(ChunkText, 400)
    FROM #rag_topk
    ORDER BY Score
    FOR JSON PATH
  );

  INSERT INTO care.CarePlanLedger
  (
    PatientId,
    Prompt,
    PatientJson,
    PlanJson,
    EvidenceJson,
    Model,
    OllamaUrl,
    HttpStatus,
    RawResponse
  )
  SELECT
    @patient_id,
    @prompt,
    CONVERT(NVARCHAR(MAX), JSON_QUERY(@patient_json,  '$')),  -- JSON -> NVARCHAR
    CONVERT(NVARCHAR(MAX), JSON_QUERY(@careplan_json,'$')),   -- JSON -> NVARCHAR (NULL ok)
    @evidence_json_text,                                      -- already NVARCHAR
    @MODEL,
    @OLLAMA_CHAT_URL,
    @http_code,
    @resp;                                                    -- raw NVARCHAR wrapper

  -- Optional: return provenance rows
  /* SELECT Title, DocType, ChunkText, Score
  FROM #rag_topk
  ORDER BY Score; */
END
GO

DECLARE @raw JSON, @plan JSON;
DECLARE @patient NVARCHAR(MAX) = N'{
  "age": 60,
  "sex": "M",
  "weight_kg": 97,
  "vitals": { "bp": "186/112", "hr": 102, "rr": 20, "spo2": "95% RA", "temp_c": 37.0 },
  "allergies": ["penicillin"],
  "comorbidities": ["hypertension", "migraine with aura"],
  "medications": ["HCTZ 12.5 mg qd"]
}';

EXEC care.usp_ai_agent_care_plan
     @prompt        = N'Bad migraine, blurry vision',
     @patient_json  = @patient,
     @patient_id    = N'PT-000182',
     @topk          = 5,
     @raw_response  = @raw OUTPUT,
     @careplan_json = @plan OUTPUT;

SELECT JSON_VALUE(@raw, '$.response.status.http.code') AS HttpCode,
        @raw as raw,
       @plan AS CarePlanJson;

-- Verify ledger append
SELECT * FROM care.CarePlanLedger;
GO