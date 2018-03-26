bulk insert tpch_workload_faster..REGION
from '/var/opt/mssql/tpch_workload_faster/region.tbl' 
with (FieldTerminator = '|', RowTerminator ='|\n',tablock)
