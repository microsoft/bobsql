bulk insert tpch_workload..PARTSUPP
from '/var/opt/mssql/tpch_workload/partsupp.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock,batchsize=1000000)
go
