USE master;
GO
DROP DATABASE IF EXISTS WideWorldImportersDW;
GO
RESTORE DATABASE WideWorldImportersDW FROM DISK = 'c:\sql_sample_databases\wideworldimportersdw-full.bak'
WITH MOVE 'wwi_primary' TO 'c:\sql_sample_databases\wideworldimportersdw.mdf',
MOVE 'wwi_userdata' TO 'c:\sql_sample_databases\wideworldimportersdw_userdata.ndf',
MOVE 'wwi_log' TO 'c:\sql_sample_databases\wideworldimportersdw.ldf',
MOVE 'wwidw_inmemory_data_1' TO 'c:\sql_sample_databases\wideworldimportersdw_inmemory_data'
go