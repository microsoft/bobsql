# Demo for looking at memory limits for Azure SQL

- Deploy an Azure SQL Database and Managed Instance (any service tier will work)
- For Azure SQL Database, you can look at these DMVs (connected to your database)

```sql
select * from sys.dm_user_db_resource_governance
go
select * from sys.dm_os_job_object
go
select * from sys.dm_os_memory_clerks
go
```
dm_os_job_object shows you true memory limit. Notice that you can look at memory clerks even though you are just connected to a database.

- For Azure SQL Managed Instance, you can look at these DMVs


```sql
select * from sys.dm_os_sys_info
go
select * from sys.dm_os_process_memory
go
select * from sys.dm_os_job_object
go
select * from sys.dm_os_memory_clerks
go
```

Notice that your memory limit in the job object may be less than what the VM provides. We don't guarantee you what VM you will be deployed to but do guarantee your memory limit.