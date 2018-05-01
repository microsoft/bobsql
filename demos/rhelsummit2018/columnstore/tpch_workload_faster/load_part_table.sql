bulk insert tpch_workload_faster..PART
from '/var/opt/mssql/tpch_workload_faster/part.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
