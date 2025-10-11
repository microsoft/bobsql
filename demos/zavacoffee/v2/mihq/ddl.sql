/* ======================================================================
   Rebuild script for core POS schema (DROPs & CREATEs)
   WARNING: This will drop and recreate tables and partitioning objects.
   ====================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* --------------------------------------------------------------
   0) Ensure schema exists
   -------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'core')
    EXEC('CREATE SCHEMA core');
GO

/* --------------------------------------------------------------
   1) DROP objects in dependency-safe order
   -------------------------------------------------------------- */
-- Child-most first
DROP TABLE IF EXISTS core.promo_applied;
DROP TABLE IF EXISTS core.pos_payment;
DROP TABLE IF EXISTS core.pos_txn_line;
DROP TABLE IF EXISTS core.pos_return;

DROP TABLE IF EXISTS core.stock_receipt_line;
DROP TABLE IF EXISTS core.stock_transfer_line;

DROP TABLE IF EXISTS core.inventory_ledger;

DROP TABLE IF EXISTS core.pos_txn;
DROP TABLE IF EXISTS core.stock_receipt;
DROP TABLE IF EXISTS core.stock_transfer;
DROP TABLE IF EXISTS core.price_change;

DROP TABLE IF EXISTS core.product;
DROP TABLE IF EXISTS core.store;
GO

/* Drop partitioning objects (no consumer tables remain) */
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_txn_month')
    DROP PARTITION SCHEME ps_txn_month;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_utc_month')
    DROP PARTITION FUNCTION pf_utc_month;
GO


/* --------------------------------------------------------------
   2) Recreate base reference tables
   -------------------------------------------------------------- */
CREATE TABLE core.store (
    store_id     INT            IDENTITY(1,1) NOT NULL,
    store_code   VARCHAR(16)    NOT NULL,
    store_name   NVARCHAR(200)  NOT NULL,
    region       NVARCHAR(100)  NULL,
    time_zone    VARCHAR(64)    NOT NULL,
    is_active    BIT            NOT NULL CONSTRAINT DF_core_store_is_active DEFAULT(1),
    CONSTRAINT PK_core_store PRIMARY KEY CLUSTERED (store_id),
    CONSTRAINT UQ_core_store_store_code UNIQUE (store_code)
);
GO

CREATE TABLE core.product (
    product_id     INT             NOT NULL,
    product_sku    VARCHAR(64)     NOT NULL,
    product_name   NVARCHAR(300)   NOT NULL,
    category       NVARCHAR(200)   NULL,
    list_price     DECIMAL(19,4)   NOT NULL,
    tax_rate       DECIMAL(9,4)    NOT NULL CONSTRAINT DF_core_product_tax_rate DEFAULT(0),
    is_active      BIT             NOT NULL CONSTRAINT DF_core_product_is_active DEFAULT(1),
    created_at_utc DATETIME2(3)    NOT NULL CONSTRAINT DF_core_product_created_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_core_product PRIMARY KEY CLUSTERED(product_id),
    CONSTRAINT UQ_core_product_sku UNIQUE (product_sku)
);
GO


/* --------------------------------------------------------------
   3) Partitioning objects (UTC-month)
   -------------------------------------------------------------- */
CREATE PARTITION FUNCTION pf_utc_month (datetime2(3))
AS RANGE RIGHT FOR VALUES
(
  '2025-07-01', '2025-08-01', '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01'
);
GO

CREATE PARTITION SCHEME ps_txn_month
AS PARTITION pf_utc_month ALL TO ([PRIMARY]);
GO


/* --------------------------------------------------------------
   4) Transactional & operational tables
   -------------------------------------------------------------- */

-- POS header (partitioned by txn_ts_utc via clustered index created after table)
CREATE TABLE core.pos_txn (
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL,            -- global ID from edge
    store_id        INT              NOT NULL,
    terminal_code   VARCHAR(32)      NOT NULL,
    business_date   DATE             NOT NULL,
    txn_ts_utc      DATETIME2(3)     NOT NULL,
    customer_id     UNIQUEIDENTIFIER NULL,                -- optional loyalty link
    subtotal_amount DECIMAL(19,4)    NOT NULL,
    tax_amount      DECIMAL(19,4)    NOT NULL CONSTRAINT DF_core_pos_txn_tax DEFAULT(0),
    total_amount    AS (ROUND(subtotal_amount + tax_amount, 4)) PERSISTED,
    payment_method  VARCHAR(32)      NOT NULL,            -- 'CASH','CARD','WALLET','MIXED'
    is_offline      BIT              NOT NULL CONSTRAINT DF_core_pos_txn_offline DEFAULT(0),
    insert_utc      DATETIME2(3)     NOT NULL CONSTRAINT DF_core_pos_txn_insert DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_core_pos_txn PRIMARY KEY NONCLUSTERED (pos_txn_id) ON [PRIMARY],
    CONSTRAINT FK_core_pos_txn_store FOREIGN KEY (store_id) REFERENCES core.store(store_id)
);
GO

-- Create the clustered index aligned to the partition scheme (after table creation)
CREATE CLUSTERED INDEX CX_core_pos_txn
ON core.pos_txn (store_id, txn_ts_utc, pos_txn_id)
ON ps_txn_month (txn_ts_utc);
GO

-- POS lines
CREATE TABLE core.pos_txn_line (
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL,
    line_no         INT              NOT NULL,
    product_id      INT              NOT NULL,
    quantity        DECIMAL(18,3)    NOT NULL,
    unit_price      DECIMAL(19,4)    NOT NULL,
    discount_amt    DECIMAL(19,4)    NOT NULL CONSTRAINT DF_core_pos_txn_line_disc DEFAULT(0),
    line_amount     AS (ROUND(quantity * unit_price - discount_amt, 4)) PERSISTED,
    CONSTRAINT PK_core_pos_txn_line PRIMARY KEY (pos_txn_id, line_no),
    CONSTRAINT CK_core_pos_txn_line_qty_pos CHECK (quantity > 0),
    CONSTRAINT FK_core_pos_txn_line_pos_txn FOREIGN KEY (pos_txn_id)
        REFERENCES core.pos_txn(pos_txn_id) ON DELETE CASCADE,
    CONSTRAINT FK_core_pos_txn_line_product FOREIGN KEY (product_id)
        REFERENCES core.product(product_id)
);
GO

CREATE INDEX IX_core_pos_txn_line_product
ON core.pos_txn_line (product_id);
GO

-- POS payments
CREATE TABLE core.pos_payment (
    payment_id      BIGINT           IDENTITY(1,1) NOT NULL,
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL,
    method          VARCHAR(32)      NOT NULL,      -- 'CASH','CARD','WALLET','GIFT'
    amount          DECIMAL(19,4)    NOT NULL,
    auth_code       VARCHAR(64)      NULL,
    provider_ref    VARCHAR(128)     NULL,
    CONSTRAINT PK_core_pos_payment PRIMARY KEY (payment_id),
    CONSTRAINT FK_core_pos_payment_pos_txn FOREIGN KEY (pos_txn_id)
        REFERENCES core.pos_txn(pos_txn_id)
);
GO

CREATE INDEX IX_core_pos_payment_txn
ON core.pos_payment (pos_txn_id);
GO

-- POS returns
CREATE TABLE core.pos_return (
    return_id       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_core_pos_return_id DEFAULT NEWSEQUENTIALID(),
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL,
    original_txn_id UNIQUEIDENTIFIER NULL,  -- original sale txn
    reason_code     VARCHAR(32)      NULL,  -- 'DEFECT','CUSTOMER','OTHER'
    refund_amount   DECIMAL(19,4)    NOT NULL,
    event_ts_utc    DATETIME2(3)     NOT NULL CONSTRAINT DF_core_pos_return_ts DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_core_pos_return PRIMARY KEY (return_id),
    CONSTRAINT FK_core_pos_return_pos_txn FOREIGN KEY (pos_txn_id)
        REFERENCES core.pos_txn(pos_txn_id)
);
GO

-- Inventory ledger (partitioned by event_ts_utc via clustered index)
CREATE TABLE core.inventory_ledger (
    ledger_id      BIGINT          IDENTITY(1,1) NOT NULL,
    store_id       INT             NOT NULL,
    product_id     INT             NOT NULL,
    event_ts_utc   DATETIME2(3)    NOT NULL,
    source         VARCHAR(32)     NOT NULL,  -- 'POS','RETURN','RECEIPT','TRANSFER_OUT','TRANSFER_IN','ADJUST'
    reference_id   UNIQUEIDENTIFIER NULL,     -- e.g., pos_txn_id or return_id
    qty_delta      DECIMAL(18,3)   NOT NULL,  -- negative = sale, positive = receipt/return
    note           NVARCHAR(200)   NULL,
    CONSTRAINT PK_core_inventory_ledger PRIMARY KEY NONCLUSTERED (ledger_id),  -- <-- FIXED: NONCLUSTERED
    CONSTRAINT FK_core_inventory_ledger_store FOREIGN KEY (store_id) REFERENCES core.store(store_id),
    CONSTRAINT FK_core_inventory_ledger_product FOREIGN KEY (product_id) REFERENCES core.product(product_id)
);
GO

CREATE CLUSTERED INDEX CX_core_inventory_ledger
ON core.inventory_ledger (store_id, event_ts_utc, ledger_id)
ON ps_txn_month (event_ts_utc);
GO

CREATE INDEX IX_core_inventory_ledger_product
ON core.inventory_ledger (product_id);
GO

-- Stock receipts
CREATE TABLE core.stock_receipt (
    receipt_id      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_core_stock_receipt_id DEFAULT NEWSEQUENTIALID(),
    store_id        INT              NOT NULL,
    received_ts_utc DATETIME2(3)     NOT NULL CONSTRAINT DF_core_stock_receipt_ts DEFAULT SYSUTCDATETIME(),
    vendor_code     VARCHAR(64)      NULL,
    po_number       VARCHAR(64)      NULL,
    note            NVARCHAR(200)    NULL,
    CONSTRAINT PK_core_stock_receipt PRIMARY KEY (receipt_id),
    CONSTRAINT FK_core_stock_receipt_store FOREIGN KEY (store_id) REFERENCES core.store(store_id)
);
GO

CREATE TABLE core.stock_receipt_line (
    receipt_id     UNIQUEIDENTIFIER NOT NULL,
    line_no        INT              NOT NULL,
    product_id     INT              NOT NULL,  -- matches core.product(product_id)
    qty_received   DECIMAL(18,3)    NOT NULL,
    CONSTRAINT PK_core_stock_receipt_line PRIMARY KEY (receipt_id, line_no),
    CONSTRAINT FK_core_stock_receipt_line_receipt FOREIGN KEY (receipt_id)
        REFERENCES core.stock_receipt(receipt_id) ON DELETE CASCADE,
    CONSTRAINT FK_core_stock_receipt_line_product FOREIGN KEY (product_id)
        REFERENCES core.product(product_id)
);
GO

-- Stock transfers
CREATE TABLE core.stock_transfer (
    transfer_id     UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_core_stock_transfer_id DEFAULT NEWSEQUENTIALID(),
    src_store_id    INT              NOT NULL,
    dst_store_id    INT              NOT NULL,
    shipped_ts_utc  DATETIME2(3)     NULL,
    received_ts_utc DATETIME2(3)     NULL,
    note            NVARCHAR(200)    NULL,
    CONSTRAINT PK_core_stock_transfer PRIMARY KEY (transfer_id),
    CONSTRAINT FK_core_stock_transfer_src FOREIGN KEY (src_store_id) REFERENCES core.store(store_id),
    CONSTRAINT FK_core_stock_transfer_dst FOREIGN KEY (dst_store_id) REFERENCES core.store(store_id)
);
GO

CREATE TABLE core.stock_transfer_line (
    transfer_id    UNIQUEIDENTIFIER NOT NULL,
    line_no        INT              NOT NULL,
    product_id     INT              NOT NULL,
    qty            DECIMAL(18,3)    NOT NULL,
    CONSTRAINT PK_core_stock_transfer_line PRIMARY KEY (transfer_id, line_no),
    CONSTRAINT CK_core_stock_transfer_line_qty_pos CHECK (qty > 0),
    CONSTRAINT FK_core_stock_transfer_line_transfer FOREIGN KEY (transfer_id)
        REFERENCES core.stock_transfer(transfer_id) ON DELETE CASCADE,
    CONSTRAINT FK_core_stock_transfer_line_product FOREIGN KEY (product_id)
        REFERENCES core.product(product_id)
);
GO

-- Price changes
CREATE TABLE core.price_change (
    price_id       BIGINT          IDENTITY(1,1) NOT NULL,
    product_id     INT             NOT NULL,
    store_id       INT             NULL, -- NULL = global
    effective_utc  DATETIME2(3)    NOT NULL,
    new_price      DECIMAL(19,4)   NOT NULL,
    CONSTRAINT PK_core_price_change PRIMARY KEY (price_id),
    CONSTRAINT FK_core_price_change_product FOREIGN KEY (product_id) REFERENCES core.product(product_id),
    CONSTRAINT FK_core_price_change_store   FOREIGN KEY (store_id)   REFERENCES core.store(store_id)
);
GO

CREATE INDEX IX_core_price_change_product_effective 
ON core.price_change (product_id, effective_utc DESC);
GO

-- Promotions applied
CREATE TABLE core.promo_applied (
    promo_id       BIGINT           IDENTITY(1,1) NOT NULL,
    pos_txn_id     UNIQUEIDENTIFIER NOT NULL,
    offer_code     VARCHAR(64)      NOT NULL,
    discount_amt   DECIMAL(19,4)    NOT NULL,
    applied_ts_utc DATETIME2(3)     NOT NULL CONSTRAINT DF_core_promo_applied_ts DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_core_promo_applied PRIMARY KEY (promo_id),
    CONSTRAINT FK_core_promo_applied_pos_txn FOREIGN KEY (pos_txn_id)
        REFERENCES core.pos_txn(pos_txn_id)
);
GO

/* ======================================================================
   Done
   ====================================================================== */