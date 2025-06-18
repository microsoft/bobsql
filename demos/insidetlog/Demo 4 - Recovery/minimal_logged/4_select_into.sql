use bulklogdb;
GO
DROP TABLE IF EXISTS bigtab2;
GO
SELECT * INTO bigtab2 FROM bigtab;
GO
SELECT [Current LSN], Operation, Context, AllocUnitName, [Log Record Length]
FROM sys.fn_dblog(NULL, NULL)
WHERE AllocUnitName = 'dbo.bigtab2';
GO
