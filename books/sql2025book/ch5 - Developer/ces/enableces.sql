USE [ContosoOrders];
GO

-- Enable CES
EXEC sys.sp_enable_event_stream;
GO

-- Create the stream group
EXEC sys.sp_drop_event_stream_group N'OrdersCESGroup';
GO
EXEC sys.sp_create_event_stream_group
@stream_group_name = N'OrdersCESGroup',
@destination_type = N'AzureEventHubsAmqp',
@destination_location = N'<AEHspace>.servicebus.windows.net/<AEH>',
@destination_credential = eventhubscred;
GO
EXEC sys.sp_add_object_to_event_stream_group N'OrdersCESGroup', N'dbo.Orders';
GO
