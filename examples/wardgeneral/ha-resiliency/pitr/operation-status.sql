/*
  Show the most recent management operation for the restored database.
  Run in master as the server-level principal.

  sqlcmd variables:
    RestoredDatabase - High Availability and Resiliency PITR target database name
*/
SET NOCOUNT ON;

SELECT
(
    SELECT TOP (1)
        CONVERT(NVARCHAR(36), session_activity_id) AS session_activity_id,
        CONVERT(NVARCHAR(128), major_resource_id) AS database_name,
        operation,
        state_desc,
        percent_complete,
        error_code,
        error_desc,
        start_time,
        last_modify_time,
        CASE
            WHEN state_desc = N'COMPLETED'
            THEN DATEDIFF_BIG(SECOND, start_time, last_modify_time)
        END AS restore_duration_seconds
    FROM sys.dm_operation_status
    WHERE CONVERT(NVARCHAR(128), major_resource_id) = N'$(RestoredDatabase)'
    ORDER BY start_time DESC
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
) AS operation_status_json;
GO
