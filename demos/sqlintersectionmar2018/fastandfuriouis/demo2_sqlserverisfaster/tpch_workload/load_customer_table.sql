bulk insert tpch_workload..CUSTOMER
from '/var/opt/mssql/tpch_workload/customer.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock)
go
