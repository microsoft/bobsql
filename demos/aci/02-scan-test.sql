/*
    Cold-cache clustered index scan test.
    CHECKPOINT + DROPCLEANBUFFERS forces reads from RBPEX/page servers.
    Pages become the dominant cost — more pages = more elapsed time.
*/
CHECKPOINT;
DBCC DROPCLEANBUFFERS;
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;

SELECT COUNT_BIG(*) AS row_count
FROM dbo.aic_demo WITH (INDEX(pk_aic_demo))
OPTION (MAXDOP 1);

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
