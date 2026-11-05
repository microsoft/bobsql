USE ContosoHR;
GO
-- Create an append-only ledger table to track T-SQL commands from the app and the "real" user who initiated the transactkion
DROP TABLE IF EXISTS [dbo].[AuditEvents];
GO
CREATE TABLE [dbo].[AuditEvents](
	[Timestamp] [Datetime2] NOT NULL DEFAULT (GETDATE()),
	[UserName] [nvarchar](255) NOT NULL,
	[Query] [nvarchar](4000) NOT NULL
	)
WITH (LEDGER = ON (APPEND_ONLY = ON));
GO
