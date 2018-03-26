bulk insert tpch_workload..REGION
from '/var/opt/mssql/tpch_workload/region.tbl' 
with (FieldTerminator = '|', RowTerminator ='|\n',tablock)
