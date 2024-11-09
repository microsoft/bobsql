use bulklogdb;
GO
DROP TABLE IF EXISTS bigtab2;
GO
SELECT * INTO bigtab2 FROM bigtab;
GO
SELECT [Current LSN], Operation, Context, AllocUnitName, [Transaction Name], *
FROM sys.fn_dblog(NULL, NULL)
GO
