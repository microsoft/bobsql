-- Create a login with a strong password
CREATE LOGIN guyinacube
WITH PASSWORD = '$StrongPassw0rd!'
GO

-- Create a user in the guyinacubedb database for the login
USE guyinacubedb;
GO

CREATE USER guyinacube FOR LOGIN guyinacube;
GO

-- Make the user the dbo for the database
ALTER AUTHORIZATION ON DATABASE::guyinacubedb TO guyinacube;
GO

GRANT SELECT ON bigtab TO guyinacube;
GO

GRANT SHOWPLAN TO guyinacube;
GO
