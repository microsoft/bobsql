CREATE USER jobcred FROM LOGIN jobcred;
GO
exec sp_addrolemember 'db_owner', 'jobcred';
GO