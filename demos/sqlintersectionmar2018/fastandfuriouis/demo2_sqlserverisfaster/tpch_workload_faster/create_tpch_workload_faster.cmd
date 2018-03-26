sqlcmd -Usa -itpch_workload_faster_ddl.sql -S%1 -P%2
call load_tpch_workload_faster %1 %2
sqlcmd -Usa -itpch_workload_faster_indexes.sql -S%1 -P%2
