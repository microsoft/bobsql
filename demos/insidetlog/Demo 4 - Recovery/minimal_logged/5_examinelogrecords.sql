USE bulklogdb;
GO
SELECT [Current LSN], Operation, Context, AllocUnitName, [Transaction Name], *
FROM sys.fn_dblog(NULL, NULL);
GO