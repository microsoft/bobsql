USE master;
GO
CREATE LOGIN dbm_login WITH PASSWORD = '<strong pwd>';
GO
CREATE USER dbm_user FOR LOGIN dbm_login;
GO