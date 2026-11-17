/*
    Beat 1 - Caldova's cloud patient-access dashboard is slow.

    Automatic tuning is asynchronous. Run this workload during demo preparation
    until 02-check-auto-index.sql confirms that Azure SQL created the index.
*/

SET NOCOUNT ON;
GO

DECLARE @StopAt datetime2(0) = DATEADD(MINUTE, 15, SYSUTCDATETIME());
DECLARE @FromAt datetime2(3);
SELECT @FromAt = DATEADD(MINUTE, -525600, SYSUTCDATETIME());

CREATE TABLE #DashboardResult
(
    AppointmentStatus varchar(20),
    SpecialtyCode tinyint,
    appointment_count bigint,
    average_wait_minutes bigint,
    instruction_bytes bigint,
    revision_count bigint
);

WHILE SYSUTCDATETIME() < @StopAt
BEGIN
    DECLARE @RegionId int = ((DATEPART(MILLISECOND, SYSUTCDATETIME()) * 17) % 100) + 1;

    INSERT #DashboardResult
        EXEC demo.usp_PatientAccessDashboard
             @ServiceRegionId = @RegionId,
             @FromAt = @FromAt;

    TRUNCATE TABLE #DashboardResult;
END;
GO

PRINT 'Workload interval complete. Run 02-check-auto-index.sql.';
GO