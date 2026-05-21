USE [zavahospital];
GO
EXEC clinical.usp_GetCurrentPatientVitals @PatientID = 123;
GO
EXEC clinical.usp_GetPatientSymptoms @PatientID = 123;
GO
-- Example A: Chest X‑ray (Imaging) — open encounter auto-resolved, Pending
EXEC clinical.usp_CreateOrder
     @PatientID        = 101,
     @ProviderID       = 3,                        -- authoring provider
     @OrderTypeCode    = N'Imaging',
     @Details          = N'Chest X‑ray (CXR) PA/Lateral; r/o focal consolidation; portable if unstable.',
     @Status           = N'Pending';
GO