/* Remove only the objects created by the Performance memory grant demo. */

SET XACT_ABORT ON;
SET NOCOUNT ON;
GO

DECLARE @QueryId BIGINT;

DECLARE QueryStoreQueries CURSOR LOCAL FAST_FORWARD FOR
    SELECT query_id
    FROM sys.query_store_query
    WHERE object_id = OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback');

OPEN QueryStoreQueries;
FETCH NEXT FROM QueryStoreQueries INTO @QueryId;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_query_store_remove_query @query_id = @QueryId;
    FETCH NEXT FROM QueryStoreQueries INTO @QueryId;
END;

CLOSE QueryStoreQueries;
DEALLOCATE QueryStoreQueries;

SELECT
    QueryStoreRowsRemaining = COUNT_BIG(*)
FROM sys.query_store_query
WHERE object_id = OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback');
GO

DROP PROCEDURE IF EXISTS clinical.DemonstrateMemoryGrantFeedback;
DROP TABLE IF EXISTS clinical.ShiftReportArchive;
GO

SELECT
    Result = N'CLEAN',
    ProcedurePresent = IIF(OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback', N'P') IS NULL, 0, 1),
    TablePresent = IIF(OBJECT_ID(N'clinical.ShiftReportArchive', N'U') IS NULL, 0, 1);
GO