sqlcmd -Usa -Q"alter database tpch_workload_faster set recovery bulk_logged" -S%1 -P%2
sqlcmd -Usa -iload_customer_table.sql -S%1 -P%2
sqlcmd -Usa -iload_lineitem_table.sql -S%1 -P%2
sqlcmd -Usa -iload_nation_table.sql -S%1 -P%2
sqlcmd -Usa -iload_orders_table.sql -S%1 -P%2
sqlcmd -Usa -iload_partsupp_table.sql -S%1 -P%2
sqlcmd -Usa -iload_part_table.sql -S%1 -P%2
sqlcmd -Usa -iload_region_table.sql -S%1 -P%2
sqlcmd -Usa -iload_supplier_table.sql -S%1 -P%2
sqlcmd -Usa -Q"alter database tpch_workload_faster set recovery full" -S%1 -P%2
