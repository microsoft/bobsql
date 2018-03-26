bulk insert tpch_workload..SUPPLIER
from '/var/opt/mssql/tpch_workload/supplier.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
