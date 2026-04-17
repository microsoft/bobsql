/*
    Automatic Index Compaction (AIC) Demo - Step 4: Enable AIC
    ==========================================================
    Enable AIC on the degraded index. No rebuild — let AIC do the work.
    Run via MSSQL extension or sqlsim.
*/

/* Enable automatic index compaction */
ALTER DATABASE CURRENT SET AUTOMATIC_INDEX_COMPACTION = ON;
GO

/* Confirm it's enabled */
SELECT name AS database_name,
       IIF(is_automatic_index_compaction_on = 1, 'ON', 'OFF') AS aic_status
FROM sys.databases
WHERE database_id = DB_ID();

PRINT 'AIC is ON. Background compaction will begin shortly.';
PRINT 'Use check-aic-progress.ps1 to monitor, then 03-scan-test.ps1 for cold cache scan.';
GO
