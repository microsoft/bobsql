-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(SqlLoginPassword)' = N'$' + N'(SqlLoginPassword)' OR LEN(N'$(SqlLoginPassword)') = 0
BEGIN
    RAISERROR('Supply SqlLoginPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
set nocount on
go
use master
go
drop database if exists test
go
DROP LOGIN [testuser]
go
create database test
go
CREATE LOGIN [testuser] WITH PASSWORD=N'$(SqlLoginPassword)', DEFAULT_DATABASE=test, CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO
use test
go
create schema BobWard
go
CREATE USER [testuser] FOR LOGIN [testuser]
GO
USE [test]
GO
ALTER ROLE [db_datareader] ADD MEMBER [testuser]
GO
use test
go
declare @count int = 50000
while (@count > 0)
begin
       declare @cmd varchar(max) = 'create table BobWard.tbl' + cast(@count as varchar(20)) + 
                                  '( id int NOT NULL PRIMARY KEY CLUSTERED IDENTITY(1,1),
                                     col1 varchar(1)
                                  )'
 
       -- print @cmd
       exec(@cmd)
 
       set @count = @count - 1
end
go
GO
SET NOEXEC OFF;
GO
