bulk insert tpch_workload_faster..ORDERS
from '/var/opt/mssql/tpch_workload_faster/orders.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go