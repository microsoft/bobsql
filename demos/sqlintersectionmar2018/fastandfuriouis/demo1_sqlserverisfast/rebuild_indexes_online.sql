use tpcc_workload
go
ALTER DATABASE tpcc_workload set recovery bulk_logged
go
ALTER INDEX [customer_i2] on customer REBUILD WITH (ONLINE=ON, MAXDOP=1, RESUMABLE=ON)
go
ALTER DATABASE tpcc_workload set recovery full
go