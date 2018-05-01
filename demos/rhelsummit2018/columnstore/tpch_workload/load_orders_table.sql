bulk insert tpch_workload..ORDERS
from '/var/opt/mssql/tpch_workload/orders.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go