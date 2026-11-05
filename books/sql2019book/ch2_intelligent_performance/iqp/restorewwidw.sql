restore filelistonly from disk = 'c:\sql_sample_databases\wideworldimportersdw-full.bak'
go
restore database WideWorldImportersDW from disk = 'c:\sql_sample_databases\wideworldimportersdw-full.bak'
with move 'wwi_primary' to 'c:\sql_sample_databases\wideworldimportersdw.mdf',
move 'wwi_userdata' to 'c:\sql_sample_databases\wideworldimportersdw_userdata.ndf',
move 'wwi_log' to 'c:\sql_sample_databases\wideworldimportersdw.ldf',
move 'wwidw_inmemory_data_1' to 'c:\sql_sample_databases\wideworldimportersdw_inmemory_data'
go