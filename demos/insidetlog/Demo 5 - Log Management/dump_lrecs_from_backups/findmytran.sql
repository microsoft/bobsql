USE findmytransaction;
GO
SELECT [Transaction Name], [Mark Name], [Operation], [Transaction ID], [Description]
FROM sys.fn_dblog(NULL, NULL),
	(SELECT [Transaction ID] tid
	FROM sys.fn_dblog(NULL, NULL)
	WHERE [Transaction Name] = 'mytransaction') [tran]
WHERE [tran].[tid] = [Transaction ID]
GO
