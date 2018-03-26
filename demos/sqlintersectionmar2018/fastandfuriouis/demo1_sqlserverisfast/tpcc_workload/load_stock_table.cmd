start sqlcmd -E -iload_stock_table_1.sql -S%1 -oload_stock_table_1.out
start sqlcmd -E -iload_stock_table_2.sql -S%1 -oload_stock_table_2.out
start sqlcmd -E -iload_stock_table_3.sql -S%1 -oload_stock_table_3.out
start sqlcmd -E -iload_stock_table_4.sql -S%1 -oload_stock_table_4.out
start sqlcmd -E -iload_stock_table_5.sql -S%1 -oload_stock_table_5.out
start sqlcmd -E -iload_stock_table_6.sql -S%1 -oload_stock_table_6.out
start sqlcmd -E -iload_stock_table_7.sql -S%1 -oload_stock_table_7.out
sqlcmd -E -iload_stock_table_8.sql -S%1 -oload_stock_table_8.out