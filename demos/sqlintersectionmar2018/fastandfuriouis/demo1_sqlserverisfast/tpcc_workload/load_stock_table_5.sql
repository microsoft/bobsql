use tpcc_workload
go
-- Load the STOCK table
--
BULK INSERT stock FROM 'c:\demos\sqlintersectionmarch2018\sql2017fastandfurious\demo1_sqlserverisfast\tpcc_workload\inputfiles\stock_5.tbl' WITH (TABLOCK, DATAFILETYPE='char', CODEPAGE='raw', FIELDTERMINATOR = '|')
go
