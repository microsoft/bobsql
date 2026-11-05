SET NOCOUNT ON;

SELECT
    e.EncounterId,
    e.AttendingProviderId,
    pr.FullName AS AttendingProvider,
    e.BedId,
    b.BedNumber,
    e.Status
FROM clinical.Encounter AS e
JOIN ops.Provider AS pr
    ON pr.ProviderId = e.AttendingProviderId
LEFT JOIN ops.Bed AS b
    ON b.BedId = e.BedId
WHERE e.EncounterId = 200375;

SELECT TOP (10)
    e.AttendingProviderId AS ProviderId,
    pr.FullName,
    ActiveEncounters = COUNT_BIG(*)
FROM clinical.Encounter AS e
JOIN ops.Provider AS pr
    ON pr.ProviderId = e.AttendingProviderId
WHERE e.Status = N'Active'
GROUP BY e.AttendingProviderId, pr.FullName
ORDER BY ActiveEncounters DESC, pr.FullName;
GO
