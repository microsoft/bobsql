USE AdventureWorksLT;
GO

-- Alter columns to use native types
ALTER TABLE [SalesLT].[Address]
ALTER COLUMN [StateProvince] NVARCHAR(50) NOT NULL;
GO

ALTER TABLE [SalesLT].[Address]
ALTER COLUMN [CountryRegion] NVARCHAR(50) NOT NULL;
GO

-- Alter columns to use native types
ALTER TABLE [SalesLT].[CustomerAddress]
ALTER COLUMN [AddressType] NVARCHAR(50) NOT NULL;
GO

-- Alter columns to use native types
ALTER TABLE [SalesLT].[Customer]
ALTER COLUMN [NameStyle] BIT NOT NULL;
GO

ALTER TABLE [SalesLT].[Customer]
ALTER COLUMN [FirstName] NVARCHAR(50) NOT NULL;
GO

ALTER TABLE [SalesLT].[Customer]
ALTER COLUMN [MiddleName] NVARCHAR(50) NULL;
GO

ALTER TABLE [SalesLT].[Customer]
ALTER COLUMN [LastName] NVARCHAR(50) NOT NULL;
GO

ALTER TABLE [SalesLT].[Customer]
ALTER COLUMN [Phone] NVARCHAR(25) NULL;
GO