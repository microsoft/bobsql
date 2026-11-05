create table bigtab (col1 int, col2 char(7000) not null);
go
-- 125000 rows = ~1000 VLFs at 1MB each
declare @x int;
set @x = 0;
while (@x < 125000)
begin
	insert into bigtab values (@x, 'x');
	set @x = @x + 1;
end;
go

checkpoint

backup database growvlf to disk = 'c:\temp\growvlf.bak' with init;
go
backup log growvlf to disk = 'c:\temp\growvlf_log.bak' with init;
go