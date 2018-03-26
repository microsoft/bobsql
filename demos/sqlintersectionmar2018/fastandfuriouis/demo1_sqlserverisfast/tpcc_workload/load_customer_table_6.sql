use tpcc_workload
go
-- Load the CUSTOMER table
--
BULK INSERT customer FROM 'c:\demos\sqlintersectionmarch2018\sql2017fastandfurious\demo1_sqlserverisfast\tpcc_workload\inputfiles\customer_6.tbl' WITH (TABLOCK, DATAFILETYPE='char', CODEPAGE='raw', FIELDTERMINATOR = '|')
go
