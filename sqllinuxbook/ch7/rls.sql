-- Demonstrate Row Level Security
--

USE master
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'GreatLakesUser')
BEGIN
	CREATE LOGIN GreatLakesUser 
	WITH PASSWORD = N'SQLRocks!00',
	     CHECK_POLICY = OFF,
		 CHECK_EXPIRATION = OFF,
		 DEFAULT_DATABASE = WideWorldImporters;
END
GO

USE WideWorldImporters;
GO
DROP USER IF EXISTS GreatLakesUser
GO
CREATE USER GreatLakesUser FOR LOGIN GreatLakesUser
GO
ALTER ROLE [Great Lakes Sales] ADD MEMBER GreatLakesUser
GO

-- Drop the security policy and function if they exist
--
DROP SECURITY POLICY IF EXISTS [Application].FilterCustomersBySalesTerritoryRole
GO
DROP FUNCTION IF EXISTS [Application].DetermineCustomerAccess
GO

-- Create the function to apply for RLS
--
CREATE FUNCTION [Application].DetermineCustomerAccess(@CityID int)
RETURNS TABLE
WITH SCHEMABINDING 
AS 
RETURN (SELECT 1 AS AccessResult 
        WHERE IS_ROLEMEMBER(N'db_owner') <> 0 
         OR IS_ROLEMEMBER((SELECT sp.SalesTerritory 
                          FROM [Application].Cities AS c
                          INNER JOIN [Application].StateProvinces AS sp
                          ON c.StateProvinceID = sp.StateProvinceID
                          WHERE c.CityID = @CityID) + N' Sales') <> 0
	    )
GO

-- The security policy that has been applied is as follows:
--
CREATE SECURITY POLICY [Application].FilterCustomersBySalesTerritoryRole
ADD FILTER PREDICATE [Application].DetermineCustomerAccess(DeliveryCityID) 
ON Sales.Customers
GO

SELECT COUNT(*) FROM Sales.Customers; -- and note count
GO

GRANT SELECT, UPDATE ON Sales.Customers TO [Great Lakes Sales]
GO

-- impersonate the user GreatLakesUser
EXECUTE AS USER = 'GreatLakesUser'
GO

-- Now note the count and which rows are returned
-- even though we have not changed the command

SELECT COUNT(*) FROM Sales.Customers; 
GO

-- Revert back to logged in user
--
REVERT
GO