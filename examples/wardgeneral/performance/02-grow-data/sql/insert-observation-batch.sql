SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RecordedAt DATETIME2(3) = SYSUTCDATETIME();
DECLARE @EncounterBucket INT = ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 4;
DECLARE @ObservationSlot INT = ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 6;

INSERT INTO clinical.Observation
    (EncounterId, PatientId, RecordedAt, ObservationType, ValueNumeric, Unit)
SELECT
    e.EncounterId,
    e.PatientId,
    DATEADD(SECOND,
        ABS(CONVERT(BIGINT, CHECKSUM(e.EncounterId, @RecordedAt))) %
            (DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, @RecordedAt)) + 1),
        e.AdmitTime),
    source.ObservationType,
    source.ValueNumeric,
    CONCAT(N'WG-PERF-GROWTH:', source.Unit)
FROM clinical.Encounter AS e
JOIN
(
    VALUES
        (0, N'HeartRate'),
        (1, N'SystolicBP'),
        (2, N'DiastolicBP'),
        (3, N'SpO2'),
        (4, N'Temperature'),
        (5, N'RespRate')
) AS selected(slot, ObservationType)
    ON selected.slot = @ObservationSlot
CROSS APPLY
(
    SELECT TOP (1)
        o.ObservationType,
        o.ValueNumeric,
        o.Unit
    FROM clinical.Observation AS o
    WHERE o.EncounterId = e.EncounterId
      AND o.ObservationType = selected.ObservationType
      AND (o.Unit IS NULL OR o.Unit NOT LIKE N'WG-PERF-%')
    ORDER BY o.RecordedAt, o.ObservationId
) AS source
WHERE e.EncounterId % 4 = @EncounterBucket;