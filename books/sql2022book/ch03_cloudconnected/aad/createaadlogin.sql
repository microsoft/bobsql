USE master;
GO
CREATE LOGIN [annahoffman@aadsqlmi.net] FROM EXTERNAL PROVIDER; 
GO
EXEC sp_addsrvrolemember @loginame='annahoffman@aadsqlmi.net', @rolename='sysadmin';
GO