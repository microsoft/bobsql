restore filelistonly from disk = 'c:\sql_sample_databases\wideworldimportersdw-full.bak'
go
restore database wideworldimportersdw from disk = 'c:\sql_sample_databases\wideworldimportersdw-full.bak'
with move 'wwi_primary' to 'c:\data\wideworldimportersdw.mdf',
move 'wwi_userdata' to 'c:\data\wideworldimportersdw_userdata.ndf',
move 'wwi_log' to 'c:\data\wideworldimportersdw.ldf',
move 'wwidw_inmemory_data_1' to 'c:\data\wideworldimportersdw_inmemory_data'
go