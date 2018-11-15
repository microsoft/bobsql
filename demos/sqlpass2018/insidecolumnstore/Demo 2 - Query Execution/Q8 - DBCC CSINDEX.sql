
set nocount on
go

use [WideWorldImportersDW]
go

dbcc traceon(3604)
;

dbcc csindex('WideWorldImportersDW', 72057594060341248 /* partition_id */, 
									 11 /* column_id */, 
									 1  /* rowgroup_id */, 
									 2  /* DICTIONARY */, 
									 1  /* print option */ )