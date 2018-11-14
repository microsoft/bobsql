USE [SecureMyDatabase]
GO
SELECT SUSER_NAME() as current_login, USER_NAME() as current_database_user
GO