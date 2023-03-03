USE schm_concurrency;
GO
DROP INDEX IF EXISTS customers.[idx_customer_tabkey];
GO
-- Try it at a lower priority
-- Create online, resumable index
CREATE CLUSTERED INDEX [idx_customer_tabkey]
ON [dbo].[customers] ([tabkey])
WITH (ONLINE = ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 5 MINUTES, ABORT_AFTER_WAIT = SELF)), RESUMABLE = ON);
GO
