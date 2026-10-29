USE [ContosoOrders];
GO

-- Check and make sure all is setup correctly
EXEC sys.sp_help_change_feed;
GO
EXEC sys.sp_help_change_feed_table @source_schema = 'dbo', @source_name = 'Orders';
GO