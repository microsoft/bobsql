-- Create a login with a strong password
CREATE LOGIN guyinacube
WITH PASSWORD = '$StrongPassw0rd!'
GO

-- Create a user in the guyinacubedb database for the login
USE guyinacubedb;
GO

CREATE USER guyinacube FOR LOGIN guyinacube;
GO

ALTER ROLE [db_owner] ADD MEMBER guyinacube;
GO

GRANT SELECT ON bigtab TO guyinacube;
GO

GRANT SHOWPLAN TO guyinacube;
GO
