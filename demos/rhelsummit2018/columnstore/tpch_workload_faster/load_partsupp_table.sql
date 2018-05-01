bulk insert tpch_workload_faster..PARTSUPP
from '/var/opt/mssql/tpch_workload_faster/partsupp.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
