-- ============================================================================
-- DEMO 2d — FK S-Lock Surprise under RCSI [+60 min format]
-- 
-- Even with RCSI on, FK validation takes S locks. Surprise!
-- Self-contained: only requires demo0 (database + tables + data).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- SETUP: Enable RCSI
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

-- TALKING POINT: "People enable RCSI and expect zero shared locks. Then
-- they see LCK_M_S waits and think it's broken. Watch this."

-- Session 1: Insert an order (FK references Accounts)
BEGIN TRAN;
    INSERT INTO dbo.Orders (AccountId, Amount) VALUES (1, 500.00);
    -- DO NOT COMMIT

-- Show the S lock from FK validation — even under RCSI:
SELECT 
    request_session_id,
    resource_type,
    resource_description,
    request_mode
FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID(N'texasrangerswillwinitthisyear')
  AND request_mode = N'S'
  AND resource_type = N'KEY';
GO

-- TALKING POINT: "See that S lock? That's FK validation. Even under RCSI,
-- SQL Server takes S locks to verify the parent row exists. This is by
-- design — correctness requires it. If you see LCK_M_S waits under RCSI,
-- check your foreign keys."

COMMIT;
GO
