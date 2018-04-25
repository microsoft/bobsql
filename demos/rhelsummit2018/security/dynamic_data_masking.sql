-- Demonstrate Dynamic Data Masking
-- 
-- Make sure to connect using a privileged user such as the database owner or sysadmin

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'GreatLakesUser')
BEGIN
	CREATE LOGIN GreatLakesUser 
	WITH PASSWORD = N'SQLRocks!00',
	     CHECK_POLICY = OFF,
		 CHECK_EXPIRATION = OFF,
		 DEFAULT_DATABASE = WideWorldImporters;
END;
GO

USE WideWorldImporters;
GO

IF NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = N'GreatLakesUser')
BEGIN
	CREATE USER GreatLakesUser FOR LOGIN GreatLakesUser;
END;
GO

ALTER ROLE [Great Lakes Sales] ADD MEMBER GreatLakesUser;
GO

/* Here is the table defintion of the Purchasing.Suppliers. The syntax MASED WITH is used to deploy DDM
CREATE TABLE [Purchasing].[Suppliers](
	[SupplierID] [int] NOT NULL,
	[SupplierName] [nvarchar](100) NOT NULL,
	[SupplierCategoryID] [int] NOT NULL,
	[PrimaryContactPersonID] [int] NOT NULL,
	[AlternateContactPersonID] [int] NOT NULL,
	[DeliveryMethodID] [int] NULL,
	[DeliveryCityID] [int] NOT NULL,
	[PostalCityID] [int] NOT NULL,
	[SupplierReference] [nvarchar](20) NULL,
	[BankAccountName] [nvarchar](50) MASKED WITH (FUNCTION = 'default()') NULL,
	[BankAccountBranch] [nvarchar](50) MASKED WITH (FUNCTION = 'default()') NULL,
	[BankAccountCode] [nvarchar](20) MASKED WITH (FUNCTION = 'default()') NULL,
	[BankAccountNumber] [nvarchar](20) MASKED WITH (FUNCTION = 'default()') NULL,
	[BankInternationalCode] [nvarchar](20) MASKED WITH (FUNCTION = 'default()') NULL,
	[PaymentDays] [int] NOT NULL,
	[InternalComments] [nvarchar](max) NULL,
	[PhoneNumber] [nvarchar](20) NOT NULL,
	[FaxNumber] [nvarchar](20) NOT NULL,
	[WebsiteURL] [nvarchar](256) NOT NULL,
	[DeliveryAddressLine1] [nvarchar](60) NOT NULL,
	[DeliveryAddressLine2] [nvarchar](60) NULL,
	[DeliveryPostalCode] [nvarchar](10) NOT NULL,
	[DeliveryLocation] [geography] NULL,
	[PostalAddressLine1] [nvarchar](60) NOT NULL,
	[PostalAddressLine2] [nvarchar](60) NULL,
	[PostalPostalCode] [nvarchar](10) NOT NULL,
	[LastEditedBy] [int] NOT NULL,
	[ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL,
	[ValidTo] [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL,
 CONSTRAINT [PK_Purchasing_Suppliers] PRIMARY KEY CLUSTERED 
(
	[SupplierID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [USERDATA],
 CONSTRAINT [UQ_Purchasing_Suppliers_SupplierName] UNIQUE NONCLUSTERED 
(
	[SupplierName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [USERDATA],
	PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo])
) ON [USERDATA] TEXTIMAGE_ON [USERDATA]
WITH
(
SYSTEM_VERSIONING = ON ( HISTORY_TABLE = [Purchasing].[Suppliers_Archive] )
)
GO
*/

-- grant SELECT rights to role principal
GRANT SELECT ON Purchasing.Suppliers TO [Great Lakes Sales];
GO

-- select with current UNMASK rights (NOTE row count and data values), assuming you are connected using a privileged user
SELECT SupplierID, SupplierName, BankAccountName, BankAccountBranch, BankAccountCode, BankAccountNumber FROM Purchasing.Suppliers;

-- impersonate the user GreatLakesUser
EXECUTE AS USER = 'GreatLakesUser';
GO

-- select with impersonated MASKED rights (NOTE row count and data values)
SELECT SupplierID, SupplierName, BankAccountName, BankAccountBranch, BankAccountCode, BankAccountNumber FROM Purchasing.Suppliers;
GO

REVERT;
GO

-- Clean-up (optional)
/*
REVOKE SELECT ON Purchasing.Suppliers TO [Great Lakes Sales];
GO
DROP USER GreatLakesUser;
GO
DROP LOGIN GreatLakesUser;
GO
*/