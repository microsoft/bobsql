-- Run separately in each scheduling database as the Entra administrator.
-- SQLCMD variable AppLoginSid comes from the app login's sys.server_principals.sid in master.
-- SQLCMD variable AppName is the App Service managed identity's display name.
IF DB_NAME() NOT IN (N'caldova-scheduling', N'northbrook-scheduling', N'ridgeview-scheduling')
    THROW 50000, 'Connect to one of the three Caldova scheduling databases.', 1;

DECLARE @AppLoginSid varbinary(85) = $(AppLoginSid);
IF @AppLoginSid IS NULL OR DATALENGTH(@AppLoginSid) <> 16
    THROW 50001, 'Supply the expected 16-byte Entra app login SID from master.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(AppName)')
    CREATE USER [$(AppName)] FROM LOGIN [$(AppName)];

IF EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE name = N'$(AppName)'
      AND (type NOT IN ('E', 'X') OR sid <> @AppLoginSid + 0xAADE)
)
    THROW 50002, 'Existing user is not mapped to the expected login; inspect the mapping before continuing.', 1;

GRANT SELECT, UPDATE ON OBJECT::dbo.AppointmentSlot TO [$(AppName)];
GRANT INSERT ON OBJECT::dbo.Appointment TO [$(AppName)];
IF OBJECT_ID(N'demo.StorageSize', N'V') IS NOT NULL
    GRANT SELECT ON OBJECT::demo.StorageSize TO [$(AppName)];
IF OBJECT_ID(N'demo.FillStorageBatch', N'P') IS NOT NULL
    GRANT EXECUTE ON OBJECT::demo.FillStorageBatch TO [$(AppName)];
IF DB_NAME() = N'caldova-scheduling'
BEGIN
    EXEC(N'GRANT SELECT ON OBJECT::network.ProviderClinic TO [$(AppName)];');
    EXEC(N'GRANT SELECT ON OBJECT::network.AppointmentAvailability TO [$(AppName)];');
END;
GO
