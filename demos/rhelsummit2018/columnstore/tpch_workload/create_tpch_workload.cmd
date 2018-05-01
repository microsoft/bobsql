sqlcmd -Usa -itpch_workload_ddl.sql -S%1 -P%2
call load_tpch_workload %1 %2
sqlcmd -Usa -itpch_workload_indexes.sql -S%1 -P%2
