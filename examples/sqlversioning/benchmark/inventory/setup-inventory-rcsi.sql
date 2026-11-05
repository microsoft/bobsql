-- Setup: Inventory Management — RCSI ON
USE master;
GO
IF DB_ID('inventory_rcsi') IS NOT NULL
    ALTER DATABASE inventory_rcsi SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
IF DB_ID('inventory_rcsi') IS NOT NULL
    DROP DATABASE inventory_rcsi;
GO
CREATE DATABASE inventory_rcsi;
GO
ALTER DATABASE inventory_rcsi SET READ_COMMITTED_SNAPSHOT ON;
GO
USE inventory_rcsi;
GO

CREATE TABLE dbo.Products (
    ProductId       INT IDENTITY(1,1) PRIMARY KEY,
    ProductName     NVARCHAR(100)   NOT NULL,
    CategoryId      INT             NOT NULL,
    QuantityOnHand  INT             NOT NULL,
    ReorderPoint    INT             NOT NULL,
    UnitPrice       DECIMAL(10,2)   NOT NULL,
    LastRestocked   DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE NONCLUSTERED INDEX IX_Products_CategoryId
    ON dbo.Products (CategoryId)
    INCLUDE (QuantityOnHand, UnitPrice, ProductName);
GO

SET NOCOUNT ON;
DECLARE @i INT = 1;
WHILE @i <= 200000
BEGIN
    INSERT INTO dbo.Products (ProductName, CategoryId, QuantityOnHand, ReorderPoint, UnitPrice)
    VALUES (
        CONCAT('Product-', @i),
        (@i - 1) % 20,
        ABS(CHECKSUM(NEWID())) % 500 + 50,
        25,
        CAST((ABS(CHECKSUM(NEWID())) % 10000) AS DECIMAL(10,2)) / 100.0 + 1.00
    );
    SET @i = @i + 1;
END;
GO

SELECT COUNT(*) AS TotalProducts, COUNT(DISTINCT CategoryId) AS Categories FROM dbo.Products;
GO
