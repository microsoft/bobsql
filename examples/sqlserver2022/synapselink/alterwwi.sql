USE WideWorldImporters;
GO

-- Drop dependent objects and then turns off versioning for Application.Cities
DROP SECURITY POLICY Application.FilterCustomersBySalesTerritoryRole;
GO
DROP FUNCTION Application.DetermineCustomerAccess;
GO
ALTER TABLE Application.Cities SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Application.Cities DROP PERIOD FOR SYSTEM_TIME;
GO
-- Drop the geography type as it is not supported
ALTER TABLE Application.Cities DROP COLUMN ValidFrom;
ALTER TABLE Application.Cities DROP COLUMN ValidTo;
ALTER TABLE Application.Cities DROP COLUMN Location;
GO
DROP TABLE Application.Cities_Archive;
GO

-- Remove versioning and some columns from Application.Countries table
ALTER TABLE Application.Countries SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Application.Countries DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Application.Countries DROP COLUMN ValidFrom;
ALTER TABLE Application.Countries DROP COLUMN ValidTo;
ALTER TABLE Application.Countries DROP COLUMN Border;
GO
DROP TABLE Application.Countries_Archive;
GO

-- Remove versioning and some columns from Application.DeliveryMethods table
ALTER TABLE Application.DeliveryMethods SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Application.DeliveryMethods DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Application.DeliveryMethods DROP COLUMN ValidFrom;
ALTER TABLE Application.DeliveryMethods DROP COLUMN ValidTo;
GO
DROP TABLE Application.DeliveryMethods_Archive;
GO

-- Remove versioning and some columns from Application.PaymentMethods table
ALTER TABLE Application.PaymentMethods SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Application.PaymentMethods DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Application.PaymentMethods DROP COLUMN ValidFrom;
ALTER TABLE Application.PaymentMethods DROP COLUMN ValidTo;
GO
DROP TABLE Application.PaymentMethods_Archive;
GO

-- Remove versioning and some columns from Application.People table
ALTER TABLE Application.People SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Application.People DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Application.People DROP COLUMN ValidFrom;
ALTER TABLE Application.People DROP COLUMN ValidTo;
ALTER TABLE Application.People DROP COLUMN OtherLanguages;
ALTER TABLE Application.People DROP COLUMN CustomFields;
ALTER TABLE Application.People DROP COLUMN HashedPassword;
ALTER TABLE Application.People DROP COLUMN UserPreferences;
ALTER TABLE Application.People DROP COLUMN Photo;
ALTER TABLE Application.People DROP COLUMN SearchName;
GO
DROP TABLE Application.People_Archive;
GO

-- Remove versioning and some columns from Application.StateProvinces table
ALTER TABLE Application.StateProvinces SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Application.StateProvinces DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Application.StateProvinces DROP COLUMN ValidFrom;
ALTER TABLE Application.StateProvinces DROP COLUMN ValidTo;
ALTER TABLE Application.StateProvinces DROP COLUMN Border;
GO
DROP TABLE Application.StateProvinces_Archive;
GO

-- Remove unsupported types from Application.SystemParameters
ALTER TABLE Application.SystemParameters DROP CONSTRAINT DF_Application_SystemParameters_LastEditedWhen;
ALTER TABLE Application.SystemParameters DROP COLUMN DeliveryLocation;
ALTER TABLE Application.SystemParameters DROP COLUMN LastEditedWhen;
ALTER TABLE Application.SystemParameters DROP COLUMN ApplicationSettings;
GO

-- Remove versioning and some columns from Application.TransactionTypes table
ALTER TABLE Application.TransactionTypes SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Application.TransactionTypes DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Application.TransactionTypes DROP COLUMN ValidFrom;
ALTER TABLE Application.TransactionTypes DROP COLUMN ValidTo;
GO
DROP TABLE Application.TransactionTypes_Archive;
GO

-- Remove unsupported types from Purchasing.PurchaseOrderLines
ALTER TABLE Purchasing.PurchaseOrderLines DROP CONSTRAINT DF_Purchasing_PurchaseOrderLines_LastEditedWhen;
ALTER TABLE Purchasing.PurchaseOrderLines DROP COLUMN LastEditedWhen;
GO

-- Remove unsupported types from Purchasing.PurchaseOrderLines
ALTER TABLE Purchasing.PurchaseOrders DROP CONSTRAINT DF_Purchasing_PurchaseOrders_LastEditedWhen;
ALTER TABLE Purchasing.PurchaseOrders DROP COLUMN LastEditedWhen;
ALTER TABLE Purchasing.PurchaseOrders DROP COLUMN Comments;
ALTER TABLE Purchasing.PurchaseOrders DROP COLUMN InternalComments;
GO

-- Remove versioning and some columns from Purchasing.SupplierCategories table
ALTER TABLE Purchasing.SupplierCategories SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Purchasing.SupplierCategories DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Purchasing.SupplierCategories DROP COLUMN ValidFrom;
ALTER TABLE Purchasing.SupplierCategories DROP COLUMN ValidTo;
GO
DROP TABLE Purchasing.SupplierCategories_Archive;
GO

-- Remove versioning and some columns from Purchasing.Suppliers table
ALTER TABLE Purchasing.Suppliers SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Purchasing.Suppliers DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Purchasing.Suppliers DROP COLUMN ValidFrom;
ALTER TABLE Purchasing.Suppliers DROP COLUMN ValidTo;
ALTER TABLE Purchasing.Suppliers DROP COLUMN DeliveryLocation;
ALTER TABLE Purchasing.Suppliers DROP COLUMN InternalComments;
GO
DROP TABLE Purchasing.Suppliers_Archive;
GO

-- Drop unsuppported data type from Purchasing.SupplierTransactions
ALTER TABLE Purchasing.SupplierTransactions DROP CONSTRAINT DF_Purchasing_SupplierTransactions_LastEditedWhen;
ALTER TABLE Purchasing.SupplierTransactions DROP COLUMN LastEditedWhen;
DROP INDEX IX_Purchasing_SupplierTransactions_IsFinalized ON Purchasing.SupplierTransactions;
ALTER TABLE Purchasing.SupplierTransactions DROP COLUMN IsFinalized;
GO

-- Remove versioning and some columns from Sales.BuyingGroups table
ALTER TABLE Sales.BuyingGroups SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Sales.BuyingGroups DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Sales.BuyingGroups DROP COLUMN ValidFrom;
ALTER TABLE Sales.BuyingGroups DROP COLUMN ValidTo;
GO
DROP TABLE Sales.BuyingGroups_Archive;
GO

-- Remove versioning and some columns from Sales.CustomerCategories table
ALTER TABLE Sales.CustomerCategories SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Sales.CustomerCategories DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Sales.CustomerCategories DROP COLUMN ValidFrom;
ALTER TABLE Sales.CustomerCategories DROP COLUMN ValidTo;
GO
DROP TABLE Sales.CustomerCategories_Archive;
GO

-- Remove versioning and some columns from Sales.Customers table
ALTER TABLE Sales.Customers SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Sales.Customers DROP PERIOD FOR SYSTEM_TIME;
GO
ALTER TABLE Sales.Customers DROP COLUMN ValidFrom;
ALTER TABLE Sales.Customers DROP COLUMN ValidTo;
ALTER TABLE Sales.Customers DROP COLUMN DeliveryLocation;
GO
DROP TABLE Sales.Customers_Archive;
GO

-- Remove unsupported types from Sales.CustomerTransactions
ALTER TABLE Sales.CustomerTransactions DROP CONSTRAINT DF_Sales_CustomerTransactions_LastEditedWhen;
ALTER TABLE Sales.CustomerTransactions DROP COLUMN LastEditedWhen;
DROP INDEX IX_Sales_CustomerTransactions_IsFinalized ON Sales.CustomerTransactions;
ALTER TABLE Sales.CustomerTransactions DROP COLUMN IsFinalized;
GO

-- Drop the datetime2 column
ALTER TABLE Sales.InvoiceLines DROP CONSTRAINT DF_Sales_InvoiceLines_LastEditedWhen;;
ALTER TABLE Sales.InvoiceLines DROP COLUMN LastEditedWhen;
GO

-- Drop the datetime2 column
ALTER TABLE Sales.Invoices DROP CONSTRAINT DF_Sales_Invoices_LastEditedWhen;;
ALTER TABLE Sales.Invoices DROP COLUMN LastEditedWhen;
DROP INDEX IX_Sales_Invoices_ConfirmedDeliveryTime ON Sales.Invoices;
ALTER TABLE Sales.Invoices DROP COLUMN ConfirmedDeliveryTime;
ALTER TABLE Sales.Invoices DROP COLUMN ConfirmedReceivedBy;
ALTER TABLE Sales.Invoices DROP COLUMN CreditNoteReason;
ALTER TABLE Sales.Invoices DROP COLUMN Comments;
ALTER TABLE Sales.Invoices DROP COLUMN DeliveryInstructions;
ALTER TABLE Sales.Invoices DROP COLUMN InternalComments;
ALTER TABLE Sales.Invoices DROP CONSTRAINT CK_Sales_Invoices_ReturnedDeliveryData_Must_Be_Valid_JSON;
ALTER TABLE Sales.Invoices DROP COLUMN ReturnedDeliveryData;
GO

-- Drop the datetime2 column
ALTER TABLE Sales.OrderLines DROP CONSTRAINT DF_Sales_OrderLines_LastEditedWhen;;
ALTER TABLE Sales.OrderLines DROP COLUMN LastEditedWhen;
DROP INDEX IX_Sales_OrderLines_Perf_20160301_01 ON Sales.OrderLines;
DROP INDEX IX_Sales_OrderLines_Perf_20160301_02 ON Sales.OrderLines;
ALTER TABLE Sales.OrderLines DROP COLUMN PickingCompletedwhen;
GO

-- Drop the datetime2 column
ALTER TABLE Sales.Orders DROP CONSTRAINT DF_Sales_Orders_LastEditedWhen;;
ALTER TABLE Sales.Orders DROP COLUMN LastEditedWhen;
ALTER TABLE Sales.Orders DROP COLUMN PickingCompletedwhen;
ALTER TABLE Sales.Orders DROP COLUMN Comments;
ALTER TABLE Sales.Orders DROP COLUMN DeliveryInstructions;
ALTER TABLE Sales.Orders DROP COLUMN InternalComments;
GO

-- Drop the datetime2 column
ALTER TABLE Sales.SpecialDeals DROP CONSTRAINT DF_Sales_SpecialDeals_LastEditedWhen;;
ALTER TABLE Sales.SpecialDeals DROP COLUMN LastEditedWhen;
GO

-- Remove versioning, datetime2 columns, and drop the history table
ALTER TABLE Warehouse.ColdRoomTemperatures SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Warehouse.ColdRoomTemperatures DROP PERIOD FOR SYSTEM_TIME;
ALTER TABLE Warehouse.ColdRoomTemperatures DROP COLUMN ValidFrom;
ALTER TABLE Warehouse.ColdRoomTemperatures DROP COLUMN ValidTo;
ALTER TABLE Warehouse.ColdRoomTemperatures DROP COLUMN RecordedWhen;
DROP TABLE Warehouse.ColdRoomTemperatures_Archive;
GO

-- Remove versioning, datetime2 columns, and drop the history table
ALTER TABLE Warehouse.Colors SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Warehouse.Colors DROP PERIOD FOR SYSTEM_TIME;
ALTER TABLE Warehouse.Colors DROP COLUMN ValidFrom;
ALTER TABLE Warehouse.Colors DROP COLUMN ValidTo;
DROP TABLE Warehouse.Colors_Archive;
GO

-- Remove versioning, datetime2 columns, and drop the history table
ALTER TABLE Warehouse.PackageTypes SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Warehouse.PackageTypes DROP PERIOD FOR SYSTEM_TIME;
ALTER TABLE Warehouse.PackageTypes DROP COLUMN ValidFrom;
ALTER TABLE Warehouse.PackageTypes DROP COLUMN ValidTo;
DROP TABLE Warehouse.PackageTypes_Archive;
GO

-- Remove versioning, datetime2 columns, and drop the history table
ALTER TABLE Warehouse.StockGroups SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Warehouse.StockGroups DROP PERIOD FOR SYSTEM_TIME;
ALTER TABLE Warehouse.StockGroups DROP COLUMN ValidFrom;
ALTER TABLE Warehouse.StockGroups DROP COLUMN ValidTo;
DROP TABLE Warehouse.StockGroups_Archive;
GO

-- Drop the datetime2 column
ALTER TABLE Warehouse.StockItemHoldings DROP CONSTRAINT DF_Warehouse_StockItemHoldings_LastEditedWhen;;
ALTER TABLE Warehouse.StockItemHoldings DROP COLUMN LastEditedWhen;
GO

-- Remove versioning, datetime2 columns, and drop the history table
ALTER TABLE Warehouse.StockItems SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE Warehouse.StockItems DROP PERIOD FOR SYSTEM_TIME;
ALTER TABLE Warehouse.StockItems DROP COLUMN ValidFrom;
ALTER TABLE Warehouse.StockItems DROP COLUMN ValidTo;
ALTER TABLE Warehouse.StockItems DROP COLUMN Tags;
ALTER TABLE Warehouse.StockItems DROP COLUMN SearchDetails;
ALTER TABLE Warehouse.StockItems DROP COLUMN MarketingComments;
ALTER TABLE Warehouse.StockItems DROP COLUMN InternalComments;
ALTER TABLE Warehouse.StockItems DROP COLUMN Photo;
ALTER TABLE Warehouse.StockItems DROP COLUMN CustomFields;

DROP TABLE Warehouse.StockItems_Archive;
GO

-- Drop the datetime2 column
ALTER TABLE Warehouse.StockItemStockGroups DROP CONSTRAINT DF_Warehouse_StockItemStockGroups_LastEditedWhen;;
ALTER TABLE Warehouse.StockItemStockGroups DROP COLUMN LastEditedWhen;
GO

-- Drop the datetime2 column
ALTER TABLE Warehouse.StockItemTransactions DROP CONSTRAINT DF_Warehouse_StockItemTransactions_LastEditedWhen;;
ALTER TABLE Warehouse.StockItemTransactions DROP COLUMN LastEditedWhen;
ALTER TABLE Warehouse.StockItemTransactions DROP COLUMN TransactionOccurredWhen;
GO

-- Drop the datetime2 column and dependent view
ALTER TABLE Warehouse.VehicleTemperatures DROP COLUMN RecordedWhen;
ALTER TABLE Warehouse.VehicleTemperatures DROP COLUMN CompressedSensorData;
GO
DROP VIEW Website.VehicleTemperatures;
GO

-- We don't need these views
DROP VIEW Website.Customers;
DROP VIEW Website.Suppliers;
GO

