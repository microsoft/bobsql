-- Demonstrate Dynamic Data Masking
-- 
-- Make sure to connect using a privileged user such as the database owner or sysadmin

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'GreatLakesUser')
BEGIN
	CREATE LOGIN GreatLakesUser 
	WITH PASSWORD = N'SQLRocks!00',
	     CHECK_POLICY = OFF,
		 CHECK_EXPIRATION = OFF,
		 DEFAULT_DATABASE = WideWorldImporters
END
GO

USE WideWorldImporters
GO
DROP USER IF EXISTS GreatLakesUser
GO
CREATE USER GreatLakesUser FOR LOGIN GreatLakesUser
GO
ALTER ROLE [Great Lakes Sales] ADD MEMBER GreatLakesUser
GO

-- grant SELECT rights to role principal
GRANT SELECT ON Purchasing.Suppliers TO [Great Lakes Sales]
GO

-- select with current UNMASK rights (NOTE row count and data values), assuming you are connected using a privileged user
SELECT SupplierID, SupplierName, BankAccountName, BankAccountBranch, BankAccountCode, BankAccountNumber FROM Purchasing.Suppliers

-- impersonate the user GreatLakesUser
EXECUTE AS USER = 'GreatLakesUser'
GO

-- select with impersonated MASKED rights (NOTE row count and data values)
SELECT SupplierID, SupplierName, BankAccountName, BankAccountBranch, BankAccountCode, BankAccountNumber FROM Purchasing.Suppliers
GO

REVERT
GO