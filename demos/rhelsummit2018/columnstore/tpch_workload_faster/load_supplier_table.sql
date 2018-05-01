bulk insert tpch_workload_faster..SUPPLIER
from '/var/opt/mssql/tpch_workload_faster/supplier.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
