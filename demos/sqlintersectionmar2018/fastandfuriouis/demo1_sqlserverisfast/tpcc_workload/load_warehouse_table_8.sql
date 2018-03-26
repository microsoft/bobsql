use tpcc_workload
go
-- Load the WAREHOUSE table
--
BULK INSERT warehouse FROM 'c:\demos\sqlintersectionmarch2018\sql2017fastandfurious\demo1_sqlserverisfast\tpcc_workload\inputfiles\warehouse_8.tbl' WITH (TABLOCK, DATAFILETYPE='char', CODEPAGE='raw', FIELDTERMINATOR = '|')
go
