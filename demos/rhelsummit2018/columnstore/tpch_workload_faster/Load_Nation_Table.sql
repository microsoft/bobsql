bulk insert tpch_workload_faster..NATION
from '/var/opt/mssql/tpch_workload_faster/nation.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock)
