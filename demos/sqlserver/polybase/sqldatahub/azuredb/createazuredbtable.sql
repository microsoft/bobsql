/****** Object:  Table [Warehouse].[StockItems]    Script Date: 2/3/2019 9:13:22 PM ******/
DROP TABLE [ModernStockItems]
GO

CREATE TABLE [ModernStockItems](
	[StockItemID] [int] NOT NULL,
	[StockItemName] [nvarchar](100) NOT NULL,
	[SupplierID] [int] NOT NULL,
	[ColorID] [int] NULL,
	[UnitPackageID] [int] NOT NULL,
	[OuterPackageID] [int] NOT NULL,
	[Brand] [nvarchar](50) NULL,
	[Size] [nvarchar](20) NULL,
	[LeadTimeDays] [int] NOT NULL,
	[QuantityPerOuter] [int] NOT NULL,
	[IsChillerStock] [bit] NOT NULL,
	[Barcode] [nvarchar](50) NULL,
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
	[LastEditedBy] [int] NOT NULL,
CONSTRAINT [PK_Warehouse_StockItems] PRIMARY KEY CLUSTERED 
(
	[StockItemID] ASC
)
)
GO