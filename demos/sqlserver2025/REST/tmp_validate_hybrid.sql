USE zavacliniq;
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

EXEC care.usp_ai_agent_care_plan_hybrid
     @prompt        = N'Bad migraine, blurry vision',
     @patient_json  = @patient,
     @patient_id    = N'PT-000182',
     @topk          = 5,
     @raw_response  = @raw OUTPUT,
     @careplan_json = @plan OUTPUT;

SELECT JSON_VALUE(@raw, '$.response.status.http.code') AS HttpCode,
       CASE WHEN @plan IS NULL THEN 'NULL' ELSE LEFT(CONVERT(NVARCHAR(MAX), @plan), 400) END AS PlanPreview;

SELECT TOP (1)
       CarePlanId,
       Model,
       HttpStatus,
       CASE WHEN PlanJson IS NULL THEN 'NULL' ELSE LEFT(CONVERT(NVARCHAR(MAX), PlanJson), 400) END AS PlanPreview,
       CreatedUtc
FROM care.CarePlanLedger
ORDER BY CarePlanId DESC;
GO
