SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @CreatedAt DATETIME2(3) = SYSUTCDATETIME();
DECLARE @EncounterBucket INT = ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 4;

INSERT INTO clinical.ClinicalNote
    (EncounterId, AuthorProviderId, NoteType, NoteText, CreatedAt)
SELECT
    e.EncounterId,
    source.AuthorProviderId,
    source.NoteType,
    CONCAT(N'WG-PERF-GROWTH: ', source.NoteText),
    DATEADD(SECOND,
        ABS(CONVERT(BIGINT, CHECKSUM(e.EncounterId, @CreatedAt))) %
            (DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, @CreatedAt)) + 1),
        e.AdmitTime)
FROM clinical.Encounter AS e
CROSS APPLY
(
    SELECT TOP (1)
        n.AuthorProviderId,
        n.NoteType,
        n.NoteText
    FROM clinical.ClinicalNote AS n
    WHERE n.EncounterId = e.EncounterId
      AND n.NoteType IN (N'Progress', N'Consult')
      AND n.NoteText NOT LIKE N'WG-PERF-%'
    ORDER BY ABS(CHECKSUM(n.NoteId, @CreatedAt)), n.NoteId
) AS source
WHERE e.EncounterId % 4 = @EncounterBucket;