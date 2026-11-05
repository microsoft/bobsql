SET NOCOUNT ON;

DECLARE @MaxEncounterId INT;
DECLARE @EncounterId INT;
DECLARE @CandidateEncounterId INT;
DECLARE @OrderedById INT;

SELECT @MaxEncounterId = MAX(EncounterId)
FROM clinical.Encounter;

SET @CandidateEncounterId = 1 + (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % @MaxEncounterId);

SELECT TOP (1) @EncounterId = EncounterId
FROM clinical.Encounter
WHERE EncounterId >= @CandidateEncounterId
ORDER BY EncounterId;

SELECT @OrderedById = AttendingProviderId
FROM clinical.Encounter
WHERE EncounterId = @EncounterId;

EXEC clinical.PlaceMedicationOrder
    @EncounterId = @EncounterId,
    @MedicationName = N'WG-PERF-SCALE:Acetaminophen',
    @OrderedById = @OrderedById,
    @Dose = N'650 mg',
    @Route = N'PO';
