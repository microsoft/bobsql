SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @CollectedAt DATETIME2(3) = SYSUTCDATETIME();
DECLARE @EncounterBucket INT = ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 4;

INSERT INTO clinical.LabResult
    (EncounterId, PatientId, OrderedById, TestName, CollectedAt, ResultedAt,
     ResultJson, Status)
SELECT
    e.EncounterId,
    e.PatientId,
    source.OrderedById,
    source.TestName,
    generated.CollectedAt,
    LEAST(DATEADD(MINUTE, 45, generated.CollectedAt),
        COALESCE(e.DischargeTime, @CollectedAt)),
    JSON_MODIFY(
        JSON_MODIFY(source.ResultJson, '$.source', N'WG-PERF-GROWTH'),
        '$.growthSequence',
        CONCAT(e.EncounterId, N'-', CONVERT(NVARCHAR(33), @CollectedAt, 126))),
    N'Resulted'
FROM clinical.Encounter AS e
CROSS APPLY
(
    SELECT TOP (1)
        l.OrderedById,
        l.TestName,
        l.ResultJson
    FROM clinical.LabResult AS l
    WHERE l.EncounterId = e.EncounterId
      AND JSON_VALUE(l.ResultJson, '$.source') IS NULL
    ORDER BY ABS(CHECKSUM(l.LabResultId, @CollectedAt)), l.LabResultId
) AS source
CROSS APPLY
(
    SELECT DATEADD(SECOND,
        ABS(CONVERT(BIGINT, CHECKSUM(e.EncounterId, @CollectedAt))) %
            (DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, @CollectedAt)) + 1),
        e.AdmitTime) AS CollectedAt
) AS generated
WHERE e.EncounterId % 4 = @EncounterBucket;