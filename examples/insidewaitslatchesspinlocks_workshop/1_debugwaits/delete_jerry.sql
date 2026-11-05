use cowboyswillreignthenfc
go
set transaction isolation level serializable
go
begin tran
delete from howboutthemcowboys where name = 'Jerry Jones'
go



