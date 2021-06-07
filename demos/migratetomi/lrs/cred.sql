USE master
GO
CREATE CREDENTIAL [https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups]
-- this name must match the container path, start with https and must not contain a forward slash at the end
WITH IDENTITY='SHARED ACCESS SIGNATURE'
-- this is a mandatory string and should not be changed
, SECRET = 'sp=racwdl&st=2021-06-03T21:11:23Z&se=2021-07-02T05:11:23Z&spr=https&sv=2020-02-10&sr=c&sig=CE7z28V6HeMtd4ASavCYgMCynMEO3H7p0tMIAee5UQI%3D'
-- this is the shared access signature key that you obtained in section 1.
GO