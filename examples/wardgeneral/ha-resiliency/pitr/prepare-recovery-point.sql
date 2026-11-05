/* Capture the source database's current UTC time for a PITR test copy. */
SET NOCOUNT ON;

SELECT
    N'RestorePointUtc=' + CONVERT(NVARCHAR(33), SYSUTCDATETIME(), 126) + N'Z';
GO
