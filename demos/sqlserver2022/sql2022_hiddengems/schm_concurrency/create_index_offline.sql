USE schm_concurrency;
GO
DROP INDEX IF EXISTS customers.[idx_customer_tabkey];
GO
-- Create offline index
CREATE CLUSTERED INDEX [idx_customer_tabkey]
ON [dbo].[customers] ([tabkey]);
GO


