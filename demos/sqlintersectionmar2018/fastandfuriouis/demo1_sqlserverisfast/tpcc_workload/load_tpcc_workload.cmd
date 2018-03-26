sqlcmd -E -Q"alter database tpcc_workload set recovery bulk_logged" -S%1
call load_customer_table %1
call load_district_table %1
call load_item_table %1
call load_new_order_table %1
call load_order_line_table %1
call load_stock_table %1
call load_warehouse_table %1
sqlcmd -E -Q"alter database tpcc_workload set recovery full" -S%1
