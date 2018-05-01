bulk insert tpch_workload_faster..CUSTOMER
from '/var/opt/mssql/tpch_workload_faster/customer.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock)
go
