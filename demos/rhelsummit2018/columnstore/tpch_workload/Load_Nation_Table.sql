bulk insert tpch_workload..NATION
from '/var/opt/mssql/tpch_workload/nation.tbl'
with (FieldTerminator = '|', RowTerminator ='|\n',tablock)
