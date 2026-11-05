SET NOCOUNT ON;

DECLARE @MaxEncounterId INT;
DECLARE @EncounterId INT;
DECLARE @CandidateEncounterId INT;

SELECT @MaxEncounterId = MAX(EncounterId)
FROM clinical.Encounter;

SET @CandidateEncounterId = 1 + (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % @MaxEncounterId);

SELECT TOP (1) @EncounterId = EncounterId
FROM clinical.Encounter
WHERE EncounterId >= @CandidateEncounterId
ORDER BY EncounterId;

EXEC clinical.GetPatientChart @EncounterId = @EncounterId;
