/* =======================================================================
   Demo: Call clinical.usp_clinical_recommendation
   Picks a patient with an open encounter and asks for a recommendation
   ======================================================================= */
USE zavahospital;
GO

-- Pick a patient who has vitals, symptoms, allergies, reason, and an open encounter
DECLARE @pid INT;
SELECT TOP (1) @pid = p.PatientID
FROM core.Patients p
JOIN core.Encounters e ON e.PatientID = p.PatientID AND e.DischargeDate IS NULL
JOIN clinical.Symptoms s ON s.EncounterID = e.EncounterID
JOIN clinical.VitalsSnapshots v ON v.EncounterID = e.EncounterID
WHERE p.Allergies IS NOT NULL
  AND e.Reason IS NOT NULL
ORDER BY NEWID();

PRINT CONCAT('Selected PatientID: ', @pid);

EXEC clinical.usp_clinical_recommendation
     @PatientID  = @pid,
     @Prompt     = N'Patient presenting with shortness of breath and elevated heart rate',
     @SearchTopN = 5;
GO
