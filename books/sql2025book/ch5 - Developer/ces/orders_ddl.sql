USE [MASTER];
GO
DROP DATABASE IF EXISTS ContosoOrders;
GO
CREATE DATABASE ContosoOrders;
GO
USE [ContosoOrders];
GO
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

-- Create the Master Key with a password.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$StrongPassw0rd';
GO
CREATE DATABASE SCOPED CREDENTIAL eventhubscred
WITH IDENTITY = '<policy>',
SECRET = '<Primary Key>';
GO

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY CLUSTERED IDENTITY,
    CustomerFirstName NVARCHAR(50),
    CustomerLastName NVARCHAR(50),
    Company NVARCHAR(100),
    SalesDate DATE,
    EstimatedShipDate DATE,
    ShippingID INT,
    ShippingLocation NVARCHAR(100),
    Product NVARCHAR(100),
    Quantity INT,
    Price DECIMAL(10, 2)
);
