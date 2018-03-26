bulk insert tpch_workload..LINEITEM
from '/var/opt/mssql/tpch_workload/lineitem.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
