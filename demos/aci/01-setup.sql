/*
    Automatic Index Compaction (AIC) Demo - Step 1: Setup
    =====================================================
    Creates a 1M-row table with a GUID clustered key and fixed-width rows.
    
    - GUID CI key distributes rows randomly across pages.
    - char(100) keeps row width constant (~130 bytes/row, ~59 rows/page).
    - REBUILD after insert gives 99.8% page density baseline.
    
    After setup, run scan-test.sql for baseline metrics,
    then 02-degrade.sql to create low page density.
*/

/* Reset to clean state */
DROP TABLE IF EXISTS dbo.aic_demo;
GO

/* Create the test table — GUID clustered key, fixed-width rows */
CREATE TABLE dbo.aic_demo
(
    id uniqueidentifier NOT NULL DEFAULT NEWID(),
    dt datetime2 NOT NULL DEFAULT SYSDATETIME(),
    val int NOT NULL DEFAULT 0,
    s char(100) NOT NULL DEFAULT REPLICATE('x', 100),
    CONSTRAINT pk_aic_demo PRIMARY KEY CLUSTERED (id)
);
GO

/* Insert 1,000,000 rows */
INSERT INTO dbo.aic_demo (id, val)
SELECT NEWID(), v.value
FROM GENERATE_SERIES(1, 1000000) AS v;
GO

/* Rebuild to get optimal density after GUID-fragmented insert */
ALTER INDEX pk_aic_demo ON dbo.aic_demo REBUILD;
GO

PRINT 'Setup complete. 1,000,000 rows, GUID CI key, fixed-width char(100) rows.';
PRINT 'Next: run scan-test.sql for BASELINE cold-cache scan, then 02-degrade.sql.';
GO
