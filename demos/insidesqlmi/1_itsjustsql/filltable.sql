drop table if exists howboutthemcowboys;
go
create table howboutthemcowboys (col1 int, col2 char(100) not null);
go
declare @x int
set @x = 0
while (@x < 10000)
begin
	insert into howboutthemcowboys values (@x, 'We will win this year')
	set @x = @x + 1
end;
go