SET NOCOUNT ON;

-- 1) No context (system session) -> fail-open, sees ALL encounters.
SELECT 'no-context (all)' AS scope, COUNT(*) AS visible FROM clinical.Encounter;

-- 2) Top attending providers by ACTIVE encounter count (candidate ActingProviderId).
SELECT TOP 5 AttendingProviderId, COUNT(*) AS active_encounters
FROM clinical.Encounter
WHERE Status = 'Active'
GROUP BY AttendingProviderId
ORDER BY active_encounters DESC;
GO

-- 3) Act as the busiest attending -> should see only THEIR encounters.
DECLARE @top INT = (
    SELECT TOP 1 AttendingProviderId
    FROM clinical.Encounter
    WHERE Status = 'Active'
    GROUP BY AttendingProviderId
    ORDER BY COUNT(*) DESC);

EXEC sys.sp_set_session_context @key = N'ProviderId', @value = @top, @read_only = 1;
EXEC sys.sp_set_session_context @key = N'Role',       @value = N'Attending', @read_only = 1;

SELECT 'acting-attending' AS scope,
       @top AS provider,
       COUNT(*) AS visible_total,
       SUM(CASE WHEN AttendingProviderId = @top THEN 1 ELSE 0 END) AS visible_mine
FROM clinical.Encounter;

-- 4) vPatientChart + vBedCensus should inherit the filter (all rows belong to @top).
SELECT 'vBedCensus occupied (mine only)' AS scope, COUNT(*) AS occupied
FROM ops.vBedCensus WHERE EncounterId IS NOT NULL;
GO
