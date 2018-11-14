restore filelistonly from disk = '/var/opt/mssql/wideworldimportersdw-full.bak'
go
restore database wideworldimportersdw from disk = '/var/opt/mssql/wideworldimportersdw-full.bak'
with move 'wwi_primary' to '/var/opt/mssql/data/wideworldimportersdw.mdf',
move 'wwi_userdata' to '/var/opt/mssql/data/wideworldimportersdw_userdata.ndf',
move 'wwi_log' to '/var/opt/mssql/data/wideworldimportersdw.ldf',
move 'wwidw_inmemory_data_1' to '/var/opt/mssql/data/wideworldimportersdw_inmemory_data'
go