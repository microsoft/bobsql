USE WideWorldImporters
GO
ALTER INDEX PK_Purchasing_PurchaseOrders
ON [Purchasing].[PurchaseOrders] 
REBUILD
WITH (ONLINE = ON, RESUMABLE = ON);
GO
