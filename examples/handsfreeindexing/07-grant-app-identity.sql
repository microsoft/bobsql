/*
    Run in SQLCMD mode after App Service deployment.

    AppClientId is the managed identity application/client ID, not its object ID.
    TYPE = E creates an external service-principal user without a Microsoft Graph lookup.
*/

SET NOCOUNT ON;
GO

DECLARE @AppClientId uniqueidentifier = '$(AppClientId)';
DECLARE @AppSid binary(16) = CONVERT(binary(16), @AppClientId);
DECLARE @CreateUserSql nvarchar(max);

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_principals
    WHERE name = '$(AppName)'
)
BEGIN
    SET @CreateUserSql =
        N'CREATE USER ' + QUOTENAME('$(AppName)') +
        N' WITH SID = ' + CONVERT(varchar(34), @AppSid, 1) +
        N', TYPE = E;';

    EXEC sys.sp_executesql @CreateUserSql;
END;
GO

GRANT EXECUTE ON OBJECT::demo.usp_PatientAccessDashboard TO [$(AppName)];
GRANT EXECUTE ON OBJECT::demo.usp_RecordDashboardMeasurement TO [$(AppName)];
GRANT EXECUTE ON OBJECT::demo.usp_CaptureIndexHealth TO [$(AppName)];
GRANT EXECUTE ON OBJECT::demo.usp_GetIndexHealthTimeline TO [$(AppName)];
GRANT EXECUTE ON OBJECT::demo.usp_IsAppReady TO [$(AppName)];
GRANT EXECUTE ON OBJECT::demo.usp_GetDemoControlState TO [$(AppName)];
GO