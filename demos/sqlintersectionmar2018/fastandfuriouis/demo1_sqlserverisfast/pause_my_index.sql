use [tpcc_workload]
go
ALTER INDEX [customer_i2] on customer PAUSE
go
select * from sys.index_resumable_operations
go