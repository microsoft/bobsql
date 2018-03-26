restore filelistonly from disk = 'c:\demos\sqlintersectionmarch2018\sql2017fastandfurious\demo1_sqlserverisfast\tpcc_workload.bak'
go
use master
go
drop database tpcc_workload
go
restore database tpcc_workload from disk = 'c:\demos\sqlintersectionmarch2018\sql2017fastandfurious\demo1_sqlserverisfast\tpcc_workload.bak'
go