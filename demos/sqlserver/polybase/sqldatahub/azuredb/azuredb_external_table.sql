USE [WideWorldImporters]
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'S0me!nfo'
GO
/*  specify credentials to external data source
*  IDENTITY: user name for external source.  
*  SECRET: password for external source.
*/
DROP DATABASE SCOPED CREDENTIAL AzureSQLDatabaseCredentials
GO
CREATE DATABASE SCOPED CREDENTIAL AzureSQLDatabaseCredentials   
WITH IDENTITY = 'thewandog', Secret = '$cprsqlserver2019'
GO
/*  LOCATION: Location string should be of format '<vendor>://<server>[:<port>]'.
*  PUSHDOWN: specify whether computation should be pushed down to the source. ON by default.
*  CREDENTIAL: the database scoped credential, created above.
*/  
DROP EXTERNAL DATA SOURCE AzureSQLDatabase
GO
CREATE EXTERNAL DATA SOURCE AzureSQLDatabase
WITH ( 
LOCATION = 'sqlserver://bwazuredb.database.windows.net',
PUSHDOWN = ON,
CREDENTIAL = AzureSQLDatabaseCredentials
)
GO
DROP SCHEMA azuresqldb
go
CREATE SCHEMA azuresqldb
GO
/*  LOCATION: sql server table/view in 'database_name.schema_name.object_name' format
*  DATA_SOURCE: the external data source, created above.
*/
DROP EXTERNAL TABLE azuresqldb.ModernStockItems
GO
CREATE EXTERNAL TABLE azuresqldb.ModernStockItems
(
	[StockItemID] [int] NOT NULL,
	[StockItemName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[SupplierID] [int] NOT NULL,
	[ColorID] [int] NULL,
	[UnitPackageID] [int] NOT NULL,
	[OuterPackageID] [int] NOT NULL,
	[Brand] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Size] [nvarchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[LeadTimeDays] [int] NOT NULL,
	[QuantityPerOuter] [int] NOT NULL,
	[IsChillerStock] [bit] NOT NULL,
	[Barcode] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[TaxRate] [decimal](18, 3) NOT NULL,
	[UnitPrice] [decimal](18, 2) NOT NULL,
	[RecommendedRetailPrice] [decimal](18, 2) NULL,
	[TypicalWeightPerUnit] [decimal](18, 3) NOT NULL,
	--[MarketingComments] [nvarchar](max) NULL,
	--[InternalComments] [nvarchar](max) NULL,
	--[Photo] [varbinary](max) NULL,
	--[CustomFields] [nvarchar](max) NULL,
	--[Tags]  AS (json_query([CustomFields],N'$.Tags')),
	--[SearchDetails]  AS (concat([StockItemName],N' ',[MarketingComments])),
	[LastEditedBy] [int] NOT NULL
)
 WITH (
 LOCATION='wwiazure.dbo.ModernStockItems',
 DATA_SOURCE=AzureSQLDatabase
)
GO
CREATE STATISTICS ModernStockItemsStats ON azuresqldb.ModernStockItems ([StockItemID]) WITH FULLSCAN
GO

SELECT * FROM azuresqldb.ModernStockItems