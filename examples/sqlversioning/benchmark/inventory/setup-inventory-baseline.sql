-- Setup: Inventory Management — Baseline (no RCSI, no ADR, no OL)
-- Creates inventory_baseline database with 200K products across 20 categories (~10K per category, triggers lock escalation)
USE master;
GO
IF DB_ID('inventory_baseline') IS NOT NULL
    ALTER DATABASE inventory_baseline SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
IF DB_ID('inventory_baseline') IS NOT NULL
    DROP DATABASE inventory_baseline;
GO
CREATE DATABASE inventory_baseline;
GO
USE inventory_baseline;
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

-- Load 200,000 products across 20 categories (~10,000 per category)
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
