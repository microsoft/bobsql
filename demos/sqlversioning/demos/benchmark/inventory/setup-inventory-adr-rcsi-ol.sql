-- Setup: Inventory Management — RCSI ON, ADR ON, OL ON
USE master;
GO
IF DB_ID('inventory_adr_rcsi_ol') IS NOT NULL
    ALTER DATABASE inventory_adr_rcsi_ol SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
IF DB_ID('inventory_adr_rcsi_ol') IS NOT NULL
    DROP DATABASE inventory_adr_rcsi_ol;
GO
CREATE DATABASE inventory_adr_rcsi_ol;
GO
ALTER DATABASE inventory_adr_rcsi_ol SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE inventory_adr_rcsi_ol SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE inventory_adr_rcsi_ol SET OPTIMIZED_LOCKING = ON;
GO
USE inventory_adr_rcsi_ol;
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
