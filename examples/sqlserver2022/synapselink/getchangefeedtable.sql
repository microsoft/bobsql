USE [WideWorldImporters];
GO
SELECT object_name(object_id), *
FROM changefeed.change_feed_tables
WHERE table_id =  '05fc889f-689f-438c-b1fd-cdb9a1333a4f';
GO