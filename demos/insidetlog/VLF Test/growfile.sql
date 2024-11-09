USE growvlf;
GO
-- Test recovery with 1000 VLFs at 1MB each
declare @x int;
set @x = 0;
declare @size bigint;
declare @newsize bigint;
declare @stmt nvarchar(1000);
while (@x < 10000)
begin
select @size = size from sys.database_files;
select @newsize = ((@size + 128)*8192)/1024
set @stmt = 'ALTER DATABASE [growvlf] MODIFY FILE (NAME = N''growvlf_log'', SIZE = '+cast(@newsize as varchar(10))+'KB)';
--select @stmt;
exec (@stmt);
set @x = @x + 1;
end;
GO
select name, size from sys.database_files
GO
select count(*) from sys.dm_db_log_info(null)
GO
select * from sys.dm_db_log_info(null);
GO