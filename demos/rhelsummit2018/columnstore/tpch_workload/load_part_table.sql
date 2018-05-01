bulk insert tpch_workload..PART
from '/var/opt/mssql/tpch_workload/part.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
