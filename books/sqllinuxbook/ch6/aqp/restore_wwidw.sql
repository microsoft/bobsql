restore filelistonly from disk = 'c:\sql_sample_databases\wideworldimportersdw-full.bak'
go
restore database wideworldimportersdw from disk = 'c:\sql_sample_databases\wideworldimportersdw-full.bak'
with move 'wwi_primary' to 'd:\data\wideworldimportersdw.mdf',
move 'wwi_userdata' to 'd:\data\wideworldimportersdw_userdata.ndf',
move 'wwi_log' to 'd:\data\wideworldimportersdw.ldf',
move 'wwidw_inmemory_data_1' to 'd:\data\wideworldimportersdw_inmemory_data'
go