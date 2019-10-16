USE [WideWorldImportersDW]
GO
UPDATE STATISTICS Fact.OrderHistory 
WITH ROWCOUNT = 3702592;
GO
ALTER TABLE [Fact].[OrderHistory] DROP CONSTRAINT [PK_Fact_OrderHistory]
GO
ALTER TABLE [Fact].[OrderHistory] ADD  CONSTRAINT [PK_Fact_OrderHistory] PRIMARY KEY NONCLUSTERED 
(
	[Order Key] ASC,
	[Order Date Key] ASC
)
GO