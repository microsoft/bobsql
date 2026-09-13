/*
    Automatic Index Compaction (AIC) Demo - Cleanup
    ================================================
    Removes all demo objects. Run via sqlsim or MSSQL extension.
*/

/* Drop demo objects */
DROP TABLE IF EXISTS dbo.aic_demo;
GO

/* Disable AIC */
ALTER DATABASE CURRENT SET AUTOMATIC_INDEX_COMPACTION = OFF;
GO

PRINT 'AIC demo cleanup complete.';
GO
