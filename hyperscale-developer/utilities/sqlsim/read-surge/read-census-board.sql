-- Ward General — READ-ONLY load: unit census board.
-- Mirrors the app Home page (ops.vBedCensus). No writes.
SET NOCOUNT ON;
DECLARE @Unit NVARCHAR(100) = (SELECT TOP 1 UnitName FROM ops.vBedCensus ORDER BY NEWID());
SELECT UnitName, BedNumber, BedStatus, EncounterId, PatientId, MRN, PatientName, AttendingProvider, AdmitTime
FROM ops.vBedCensus
WHERE (@Unit IS NULL OR UnitName = @Unit)
  AND EncounterId IS NOT NULL
ORDER BY UnitName, BedNumber;
