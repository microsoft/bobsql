sqlcmd -E -itpcc_workload_ddl.sql -S%1
call load_tpcc_workload %1
sqlcmd -E -itpcc_workload_indexes.sql -S%1
