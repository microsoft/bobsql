USE master
GO
BACKUP DATABASE [baylorbearsnationalchamps]
TO URL = 'https://storageaccountbwmig85e1.blob.core.windows.net/sqlbackups/baylorbearsnationalchamps.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO

https://storageaccountbwmig85e1.blob.core.windows.net/sqlbackups
sp=racwdl&st=2021-04-09T15:47:04Z&se=2021-05-08T23:47:04Z&spr=https&sv=2020-02-10&sr=c&sig=a1mseAtS%2BGpzIStVQ5DqyBlQKn%2FVd1pYgO%2B2%2BbmrIK4%3D