USE [zavapos];
GO

/* ===========================================================
   Database: EdgeStore (logical)
   Schema:   edge
   Purpose:  POS + Inventory at edge with self-serve kiosk
             and vector search logging.
   Note:     Ensure compat level 170 for REGEXP_LIKE in SQL 2025.
   =========================================================== */

--USE EdgeStore; -- uncomment if needed

/* 1) Create schema if not exists */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'edge')
    EXEC('CREATE SCHEMA edge');
GO

/* 2) Drop all constraints in the 'edge' schema (if any)
      Order: Foreign Keys -> Check -> Default -> Unique -> Primary Keys */
DECLARE @sql NVARCHAR(MAX) = N'';

-------------------------------------------------------------------------------
-- 2a) Foreign keys (drop referencing constraints first)
-------------------------------------------------------------------------------
SELECT @sql = @sql + N'
ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) +
N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
FROM sys.foreign_keys fk
JOIN sys.tables t     ON t.object_id = fk.parent_object_id
JOIN sys.schemas s    ON s.schema_id = t.schema_id
WHERE s.name = N'edge';

-------------------------------------------------------------------------------
-- 2b) Check constraints (includes unnamed ones)
-------------------------------------------------------------------------------
SELECT @sql = @sql + N'
ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) +
N' DROP CONSTRAINT ' + QUOTENAME(cc.name) + N';'
FROM sys.check_constraints cc
JOIN sys.tables t   ON t.object_id = cc.parent_object_id
JOIN sys.schemas s  ON s.schema_id = t.schema_id
WHERE s.name = N'edge';

-------------------------------------------------------------------------------
-- 2c) Default constraints (system‑named allowed)
-------------------------------------------------------------------------------
SELECT @sql = @sql + N'
ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) +
N' DROP CONSTRAINT ' + QUOTENAME(dc.name) + N';'
FROM sys.default_constraints dc
JOIN sys.tables t   ON t.object_id = dc.parent_object_id
JOIN sys.schemas s  ON s.schema_id = t.schema_id
WHERE s.name = N'edge';

-------------------------------------------------------------------------------
-- 2d) Unique & Primary Key constraints
-------------------------------------------------------------------------------
SELECT @sql = @sql + N'
ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) +
N' DROP CONSTRAINT ' + QUOTENAME(kc.name) + N';'
FROM sys.key_constraints kc
JOIN sys.tables t   ON t.object_id = kc.parent_object_id
JOIN sys.schemas s  ON s.schema_id = t.schema_id
WHERE s.name = N'edge'
  AND kc.[type] IN ('PK','UQ');

IF (@@TRANCOUNT = 0) BEGIN TRAN;
BEGIN TRY
    EXEC sys.sp_executesql @sql;
    COMMIT;
END TRY
BEGIN CATCH
    IF (@@TRANCOUNT > 0) ROLLBACK;
    THROW;
END CATCH
GO

/* 3) Drop tables in dependency order (children before parents) */
DROP TABLE IF EXISTS edge.inventory;
DROP TABLE IF EXISTS edge.pos_terminal;
DROP TABLE IF EXISTS edge.product_Embeddings;
DROP TABLE IF EXISTS edge.product;
DROP TABLE IF EXISTS edge.store;
GO

-- Stores
DROP TABLE IF EXISTS edge.store;
GO
CREATE TABLE edge.store (
    store_id        INT            IDENTITY(1,1) PRIMARY KEY,
    store_code      VARCHAR(16)    NOT NULL UNIQUE,
    store_name      NVARCHAR(200)  NOT NULL,
    StreetAddress   NVARCHAR(200)  NOT NULL,
    City            NVARCHAR(100)  NOT NULL,
    StateCode       NCHAR(2)       NOT NULL,
    ZipCode         NVARCHAR(10)   NOT NULL,
    -- zip regex check
    CONSTRAINT CK_Stores_ZipCode_RegEx
        CHECK (REGEXP_LIKE(ZipCode, '^\d{5}(-\d{4})?$', 'c'))
);
GO

-- POS terminals (supports KIOSK vs REGISTER)
DROP TABLE IF EXISTS edge.pos_terminal;
GO
CREATE TABLE edge.pos_terminal (
    terminal_id     INT            IDENTITY(1,1) PRIMARY KEY,
    store_id        INT            NOT NULL
        REFERENCES edge.store(store_id),
    terminal_code   VARCHAR(32)    NOT NULL,
    terminal_type   VARCHAR(16)    NOT NULL DEFAULT('REGISTER')
        CHECK (terminal_type IN ('REGISTER','KIOSK')),
    is_active       BIT            NOT NULL DEFAULT(1),
    CONSTRAINT UQ_pos_terminal UNIQUE (store_id, terminal_code)
);
GO
CREATE INDEX IX_pos_terminal_type ON edge.pos_terminal (terminal_type);
GO

DROP TABLE IF EXISTS edge.product;
GO
-- Product catalog (assigned by HQ; not identity here)
CREATE TABLE edge.product (
    product_id          INT         NOT NULL,          
    product_sku         VARCHAR(64)    NOT NULL,
    product_name        NVARCHAR(300)  NOT NULL,
    product_desc        NVARCHAR(2000) NOT NULL,
    product_attribute   JSON NOT NULL,
    list_price          DECIMAL(19,4)  NOT NULL,
    tax_rate            DECIMAL(9,4)   NOT NULL DEFAULT(0),
    is_active           BIT            NOT NULL DEFAULT(1),
    CONSTRAINT PK_edge_product PRIMARY KEY (product_id),
    CONSTRAINT UQ_edge_product_sku UNIQUE (product_sku)
);

-- Product embedding table
DROP TABLE IF EXISTS edge.product_embeddings;
GO
CREATE TABLE edge.product_embeddings(
   product_id INT NOT NULL PRIMARY KEY CLUSTERED ,
   embeddings vector(768) NOT NULL
);
GO

DROP TABLE IF EXISTS edge.inventory;
GO
-- On-hand inventory per store
CREATE TABLE edge.inventory (
    store_id        INT            NOT NULL
        REFERENCES edge.store(store_id),
    product_id      INT        NOT NULL
        REFERENCES edge.product(product_id),
    on_hand_qty     DECIMAL(18,3)  NOT NULL DEFAULT(0),
    last_updated_at DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_edge_inventory PRIMARY KEY (store_id, product_id)
);