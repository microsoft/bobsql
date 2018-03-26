bulk insert tpch_workload_faster..LINEITEM
from '/var/opt/mssql/tpch_workload_faster/lineitem.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
