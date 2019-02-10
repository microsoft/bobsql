USE [WideWorldImporters]
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'S0me!nfo'
GO
/*  specify credentials to external data source
*  IDENTITY: user name for external source.  
*  SECRET: password for external source.
*/
DROP DATABASE SCOPED CREDENTIAL CosmosDBCredentials
GO
CREATE DATABASE SCOPED CREDENTIAL CosmosDBCredentials   
WITH IDENTITY = 'wwi', Secret = 'hSoxMUeEgNjeeWh4FTz5jmGRlSN4Ko6HoYqiJsbleFzewe86EEXJrvwkAqBgitypJdjUbeJqnTVNBO6NUa0DZQ=='
GO
/*  LOCATION: Location string should be of format '<vendor>://<server>[:<port>]'.
*  PUSHDOWN: specify whether computation should be pushed down to the source. ON by default.
*  CREDENTIAL: the database scoped credential, created above.
*/  
DROP EXTERNAL DATA SOURCE CosmosDB
GO
CREATE EXTERNAL DATA SOURCE CosmosDB
WITH ( 
LOCATION = 'mongodb://wwi.documents.azure.com:10255',
PUSHDOWN = ON,
CREDENTIAL = CosmosDBCredentials
)
GO
DROP SCHEMA cosmosdb
go
CREATE SCHEMA cosmosdb
GO
/*  LOCATION: sql server table/view in 'database_name.schema_name.object_name' format
*  DATA_SOURCE: the external data source, created above.
*/
DROP EXTERNAL TABLE cosmosdb.Orders
GO
CREATE EXTERNAL TABLE cosmosdb.Orders
(
	[_id] NVARCHAR(100) NOT NULL,
	[id] NVARCHAR(100) NOT NULL,
	[OrderID] NVARCHAR(100) NOT NULL,
	[CustomerName] NVARCHAR(100) NOT NULL,
	[CustomerContact] NVARCHAR(100) NOT NULL,
	[OrderDate] NVARCHAR(100) NOT NULL,
	[CustomerPO] NVARCHAR(100) NULL,
	[ExpectedDeliverDate] NVARCHAR(100) NOT NULL
)
 WITH (
 LOCATION='WideWorldImporters.Orders',
 DATA_SOURCE=CosmosDB
)
GO
CREATE STATISTICS CosmosDBOrderDateStats ON cosmosdb.Orders ([OrderDate]) WITH FULLSCAN
GO

