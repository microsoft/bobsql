SET NOCOUNT ON;

DECLARE @MaxEncounterId INT;
DECLARE @EncounterId INT;
DECLARE @CandidateEncounterId INT;
DECLARE @OrderedById INT;
DECLARE @Wbc DECIMAL(4, 1) = 4.0 + ((ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 110) / 10.0);
DECLARE @ResultJson JSON;

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

SET @ResultJson = JSON_OBJECT(
    'panel': N'CBC',
    'source': N'WG-PERF-SCALE',
    'analytes': JSON_ARRAY(
        JSON_OBJECT(
            'name': N'WBC',
            'unit': N'K/uL',
            'refLow': 4.5,
            'refHigh': 11.0,
            'value': @Wbc
        )
    )
);

EXEC clinical.FileLabResult
    @EncounterId = @EncounterId,
    @OrderedById = @OrderedById,
    @TestName = N'CBC',
    @ResultJson = @ResultJson;
