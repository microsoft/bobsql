/*
    Show Azure SQL's current missing-index recommendation for the dashboard table.
    This script reports evidence only. It never creates an index.
*/

SET NOCOUNT ON;
GO

DECLARE @ObjectId int = OBJECT_ID('demo.PatientAccessActivity');

;WITH Recommendations AS
(
    SELECT missing_index_details.index_handle,
           missing_index_details.equality_columns,
           missing_index_details.inequality_columns,
           missing_index_details.included_columns,
           group_stats.user_seeks,
           group_stats.user_scans,
           group_stats.avg_total_user_cost,
           group_stats.avg_user_impact,
           CONVERT
           (
               decimal(18,2),
               group_stats.avg_total_user_cost
               * group_stats.avg_user_impact
               * (group_stats.user_seeks + group_stats.user_scans)
           ) AS estimated_improvement
    FROM sys.dm_db_missing_index_details AS missing_index_details
    JOIN sys.dm_db_missing_index_groups AS missing_index_groups
      ON missing_index_groups.index_handle = missing_index_details.index_handle
    JOIN sys.dm_db_missing_index_group_stats AS group_stats
      ON group_stats.group_handle = missing_index_groups.index_group_handle
    WHERE missing_index_details.database_id = DB_ID()
      AND missing_index_details.object_id = @ObjectId
)
SELECT TOP (5)
       OBJECT_SCHEMA_NAME(@ObjectId) AS schema_name,
       OBJECT_NAME(@ObjectId) AS table_name,
       equality_columns,
       inequality_columns,
       included_columns,
       user_seeks,
       user_scans,
       CONVERT(decimal(9,2), avg_user_impact) AS average_user_impact_percent,
       estimated_improvement,
       CONCAT
       (
           'CREATE INDEX [IX_Recommended_PatientAccessActivity] ON ',
           QUOTENAME(OBJECT_SCHEMA_NAME(@ObjectId)),
           '.',
           QUOTENAME(OBJECT_NAME(@ObjectId)),
           ' (',
           CONCAT_WS(', ', equality_columns, inequality_columns),
           ')',
           IIF(included_columns IS NULL, '', CONCAT(' INCLUDE (', included_columns, ')')),
           ';'
       ) AS create_index_example
FROM Recommendations
ORDER BY estimated_improvement DESC;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.dm_db_missing_index_details
    WHERE database_id = DB_ID()
      AND object_id = OBJECT_ID('demo.PatientAccessActivity')
)
BEGIN
    PRINT 'No missing-index recommendation is currently cached for demo.PatientAccessActivity.';
    PRINT 'Run 01-workload.sql again, then rerun this script.';
END;
GO
