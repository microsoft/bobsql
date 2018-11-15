set nocount on
go

-----------------------------------------------------------------------------------------------------
-- Use DBCC SHOWTEXT to walk the TEXT chain.
--
dbcc traceon(3604)
;
dbcc showtext('WideWorldImportersDW', 0x0000E70900000000D05C020003000100) with no_infomsgs
go