use master
go
drop database if exists baylorbearsnationalchamps;
go
create database baylorbearsnationalchamps;
go
use baylorbearsnationalchamps;
go
drop table if exists wearethechampions
go
create table wearethechampions (col1 int, col2 char(7000));
go
set nocount on
go
declare @x int
set @x = 0
while (@x < 500000)
begin
	insert into wearethechampions values (@x, 'no time for losers because we are the champions of the world');
	set @x = @x + 1;
end
go
set nocount off
go