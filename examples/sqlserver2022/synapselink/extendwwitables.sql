USE [WideWorldImporters];
GO
DROP TABLE IF EXISTS [Warehouse].[Vehicles];
GO
CREATE TABLE [Warehouse].[Vehicles](
	[Vehicle_Registration] [nchar](20) NOT NULL,
	[Vehicle_Type] [nchar](20) NULL,
	[Vehicle_State] [nvarchar](100) NULL,
	[Vehicle_City] [nvarchar](100) NULL,
	[Vehicle_Status] [nvarchar](10) NULL,
PRIMARY KEY CLUSTERED 
(
	[Vehicle_Registration] ASC
));
GO
DROP TABLE IF EXISTS [Warehouse].[Vehicle_StockItems];
GO
CREATE TABLE [Warehouse].[Vehicle_StockItems](
	[Vehicle_Registration] [nchar](20) NOT NULL,
	[StockItemID] [int] NOT NULL
PRIMARY KEY CLUSTERED 
(
	[Vehicle_Registration] ASC,
	[StockItemID] ASC
));
GO

