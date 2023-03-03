drop table if exists tab;
go
create table tab (col1 int);
go
insert into tab values (1);
go

begin tran
delete from tab;
go