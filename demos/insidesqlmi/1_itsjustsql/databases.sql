select name, physical_database_name, * 
from sys.databases;
go
select db_name(database_id) as dbname, * from sys.master_files
order by dbname
go