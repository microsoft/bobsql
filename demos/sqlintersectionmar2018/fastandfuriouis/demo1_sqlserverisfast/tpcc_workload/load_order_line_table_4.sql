use tpcc_workload
go
-- Load the ORDER_LINE table
--
BULK INSERT order_line FROM 'c:\demos\sqlintersectionmarch2018\sql2017fastandfurious\demo1_sqlserverisfast\tpcc_workload\inputfiles\order_line_4.tbl' WITH (TABLOCK, DATAFILETYPE='char', CODEPAGE='raw', FIELDTERMINATOR = '|')
go
