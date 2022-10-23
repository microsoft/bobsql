-- Force immediate download of latest published policies
USE master;
GO
exec sp_external_policy_refresh reload;
GO