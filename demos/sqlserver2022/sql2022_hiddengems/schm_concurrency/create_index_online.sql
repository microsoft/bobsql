USE schm_concurrency;
GO
DROP INDEX IF EXISTS customers.[idx_customer_tabkey];
GO
-- Create online, resumable index
CREATE CLUSTERED INDEX [idx_customer_tabkey]
ON [dbo].[customers] ([tabkey])
WITH (ONLINE = ON, RESUMABLE = ON);
GO

