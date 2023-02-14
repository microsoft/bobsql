SELECT @@SPID;
GO
SELECT * FROM sys.objects
CROSS JOIN sys.columns
CROSS JOIN sys.messages;
go