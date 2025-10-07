/* ===========================================================
   Database: EdgeStore (logical)
   Schema:   edge
   Purpose:  POS + Inventory at edge with self-serve kiosk
             and vector search logging.
   =========================================================== */

-- Create schema if not exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'edge')
    EXEC('CREATE SCHEMA edge');
GO

/* ------------------------------
   1) Core reference tables
   ------------------------------ */

-- Stores
DROP TABLE IF EXISTS edge.store;
GO
CREATE TABLE edge.store (
    store_id        INT            IDENTITY(1,1) PRIMARY KEY,
    store_code      VARCHAR(16)    NOT NULL UNIQUE,
    store_name      NVARCHAR(200)  NOT NULL,
    time_zone       VARCHAR(64)    NOT NULL,
    is_active       BIT            NOT NULL DEFAULT(1)
);
GO

-- POS terminals (supports KIOSK vs REGISTER vs MOBILE)
DROP TABLE IF EXISTS edge.pos_terminal;
GO
CREATE TABLE edge.pos_terminal (
    terminal_id     INT            IDENTITY(1,1) PRIMARY KEY,
    store_id        INT            NOT NULL
        REFERENCES edge.store(store_id),
    terminal_code   VARCHAR(32)    NOT NULL,
    terminal_type   VARCHAR(16)    NOT NULL DEFAULT('REGISTER')
        CHECK (terminal_type IN ('REGISTER','KIOSK','MOBILE')),
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
    product_id      BIGINT         NOT NULL,          -- stable HQ ID
    product_sku     VARCHAR(64)    NOT NULL,
    product_name    NVARCHAR(300)  NOT NULL,
    product_desc    NVARCHAR(2000) NULL,
    category        NVARCHAR(200)  NULL,
    list_price      DECIMAL(19,4)  NOT NULL,
    tax_rate        DECIMAL(9,4)   NOT NULL DEFAULT(0),
    is_active       BIT            NOT NULL DEFAULT(1),
    CONSTRAINT PK_edge_product PRIMARY KEY (product_id),
    CONSTRAINT UQ_edge_product_sku UNIQUE (product_sku)
);

-- Product embedding table
DROP TABLE IF EXISTS edge.Product_Embeddings;
GO
CREATE TABLE edge.Product_Embeddings(
    product_id BIGINT NOT NULL,
    product_embeddings vector(1536) NOT NULL
);
GO

DROP TABLE IF EXISTS edge.inventory;
GO
-- On-hand inventory per store
CREATE TABLE edge.inventory (
    store_id        INT            NOT NULL
        REFERENCES edge.store(store_id),
    product_id      BIGINT         NOT NULL
        REFERENCES edge.product(product_id),
    on_hand_qty     DECIMAL(18,3)  NOT NULL DEFAULT(0),
    last_updated_at DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_edge_inventory PRIMARY KEY (store_id, product_id)
);