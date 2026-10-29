SET NOCOUNT ON;

SELECT
    HasSchema = CASE
        WHEN OBJECT_ID(N'clinical.Patient') IS NOT NULL
         AND OBJECT_ID(N'clinical.GetPatientChart') IS NOT NULL THEN 1
        ELSE 0
    END,
    PatientCount = CASE
        WHEN OBJECT_ID(N'clinical.Patient') IS NULL THEN -1
        ELSE (SELECT COUNT(*) FROM clinical.Patient)
    END;
GO
