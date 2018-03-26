-- Create a login and user
--
use master
go
if exists (select * from sys.server_principals where name = 'dbm_login')
	DROP LOGIN dbm_login
go
CREATE LOGIN dbm_login WITH PASSWORD = 'Sql2017isfast';
go
if exists (select * from sys.database_principals where name = 'dbm_user')
	DROP USER dbm_user
go
CREATE USER dbm_user FOR LOGIN dbm_login;
go