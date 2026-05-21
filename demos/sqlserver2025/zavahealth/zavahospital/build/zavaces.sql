/* =======================================================================
   Azure Event Streams (CES) wiring for clinical.Orders -> Azure Event Hubs.
   AZURE SQL ONLY -- not used by the on-prem SQL Server 2025 demo.

   Replace the placeholders below before running, or pass them as sqlcmd
   variables with -v:
     sqlcmd -S <server> -d <db> -E -i zavaces.sql ^
        -v MasterKeyPassword="<strong-password>" ^
           EventHubNamespace="<your-namespace>" ^
           EventHubName="<your-eventhub>" ^
           EventHubPolicy="<your-sas-policy-name>" ^
           EventHubSasKey="<your-sas-key>"
   ======================================================================= */
:setvar MasterKeyPassword   "REPLACE_WITH_STRONG_PASSWORD"
:setvar EventHubNamespace   "REPLACE_WITH_NAMESPACE"
:setvar EventHubName        "REPLACE_WITH_EVENTHUB"
:setvar EventHubPolicy      "REPLACE_WITH_SAS_POLICY"
:setvar EventHubSasKey      "REPLACE_WITH_SAS_KEY"

-- Create the Master Key with a password.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MasterKeyPassword)';
GO

DROP DATABASE SCOPED CREDENTIAL zavaeventcreds;
GO
CREATE DATABASE SCOPED CREDENTIAL zavaeventcreds
    WITH IDENTITY = '$(EventHubPolicy)',
    SECRET = '$(EventHubSasKey)';
GO

EXEC sys.sp_disable_event_stream;
GO
EXEC sys.sp_enable_event_stream;
GO

EXEC sys.sp_create_event_stream_group
    @stream_group_name =      N'zavaeventstreamgroup',
    @destination_type =       N'AzureEventHubsAmqp',
    @destination_location =   N'$(EventHubNamespace).servicebus.windows.net/$(EventHubName)',
    @destination_credential = zavaeventcreds
GO

EXEC sys.sp_add_object_to_event_stream_group
    N'zavaeventstreamgroup',
    N'clinical.Orders';
GO

EXEC sp_help_change_feed;
GO
EXEC sp_help_change_feed_table @source_schema = 'clinical', @source_name = 'Orders';
GO
SELECT * FROM sys.dm_change_feed_log_scan_sessions;
GO
SELECT * 
FROM sys.dm_change_feed_errors 
ORDER BY entry_time DESC;