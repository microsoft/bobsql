-- Enable Change Event Streaming (preview) from dbo.SupportTicket to Azure Event
-- Hubs, authenticating with the logical server's system-assigned managed
-- identity. No key, no SAS token, no connection string.
--
-- Syntax verified against:
-- learn.microsoft.com/sql/relational-databases/track-changes/change-event-streaming/configure
--
-- destination_type MUST be 'AzureEventHubs' on Azure SQL Database. It is the
-- only accepted value. AzureEventHubsAMQP and AzureEventHubsApacheKafka were
-- deprecated for new stream groups on 2026-08-15 and now fail with Msg 23626.
--
-- Expects substituted variables: DmkPassword, CredentialName, StreamGroupName,
-- DestinationLocation, TableName

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- 1. Database master key.
-- The password is generated at deploy time and thrown away. On Azure SQL the
-- master key is also protected by the service master key, so nothing ever needs
-- to supply this password again.
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(DmkPassword)';
    PRINT 'Created the database master key.';
END
ELSE
    PRINT 'Database master key already exists.';
GO

-- 2. Database scoped credential pointing at the server's managed identity.
IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = '$(CredentialName)')
BEGIN
    CREATE DATABASE SCOPED CREDENTIAL [$(CredentialName)]
        WITH IDENTITY = 'Managed Identity';
    PRINT 'Created the database scoped credential.';
END
ELSE
    PRINT 'Database scoped credential already exists.';
GO

-- 3. Enable event streaming on the database.
-- These three procs have no companion catalog view to test first, so re-runs
-- are expected to report "already enabled". 05-verify.ps1 is the real gate.
BEGIN TRY
    EXEC sys.sp_enable_change_event_stream;
    PRINT 'Event streaming enabled.';
END TRY
BEGIN CATCH
    PRINT 'sp_enable_change_event_stream: ' + ERROR_MESSAGE();
END CATCH
GO

-- 4. Create the stream group.
BEGIN TRY
    EXEC sys.sp_create_change_event_stream_group
        @stream_group_name      = N'$(StreamGroupName)',
        @destination_type       = N'AzureEventHubs',
        @destination_location   = N'$(DestinationLocation)',
        @destination_credential = [$(CredentialName)],
        @max_message_size_kb    = 256,
        @partition_key_scheme   = N'None';
    PRINT 'Stream group created.';
END TRY
BEGIN CATCH
    PRINT 'sp_create_change_event_stream_group: ' + ERROR_MESSAGE();
END CATCH
GO

-- 5. Add the table to the group.
BEGIN TRY
    EXEC sys.sp_add_object_to_change_event_stream_group
        @stream_group_name = N'$(StreamGroupName)',
        @object_name       = N'$(TableName)';
    PRINT 'Table added to the stream group.';
END TRY
BEGIN CATCH
    PRINT 'sp_add_object_to_change_event_stream_group: ' + ERROR_MESSAGE();
END CATCH
GO

PRINT '';
PRINT 'Current stream groups:';
EXEC sys.sp_help_change_event_stream_groups;
GO

PRINT '';
PRINT 'Tables in stream groups:';
EXEC sys.sp_help_change_event_stream_tables;
GO
