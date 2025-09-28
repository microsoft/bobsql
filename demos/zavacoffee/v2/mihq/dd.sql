CREATE SCHEMA core AUTHORIZATION dbo;

CREATE TABLE core.store (
    store_id     INT           IDENTITY(1,1) PRIMARY KEY,
    store_code   VARCHAR(16)   NOT NULL UNIQUE,
    store_name   NVARCHAR(200) NOT NULL,
    region       NVARCHAR(100) NULL,
    time_zone    VARCHAR(64)   NOT NULL,
    is_active    BIT           NOT NULL DEFAULT(1)
);

CREATE TABLE core.product (
    product_id     BIGINT         IDENTITY(1000,1) PRIMARY KEY,
    product_sku    VARCHAR(64)    NOT NULL UNIQUE,
    product_name   NVARCHAR(300)  NOT NULL,
    category       NVARCHAR(200)  NULL,
    list_price     DECIMAL(19,4)  NOT NULL,
    tax_rate       DECIMAL(9,4)   NOT NULL DEFAULT(0),
    is_active      BIT            NOT NULL DEFAULT(1),
    created_at_utc DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Month-based partitioning by UTC timestamp
CREATE PARTITION FUNCTION pf_utc_month (datetime2(3))
AS RANGE RIGHT FOR VALUES
(
  '2025-07-01', '2025-08-01', '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01'
);

CREATE PARTITION SCHEME ps_txn_month
AS PARTITION pf_utc_month ALL TO ([PRIMARY]);

CREATE TABLE core.pos_txn (
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL,            -- from edge (global)
    store_id        INT              NOT NULL REFERENCES core.store(store_id),
    terminal_code   VARCHAR(32)      NOT NULL,
    business_date   DATE             NOT NULL,
    txn_ts_utc      DATETIME2(3)     NOT NULL,
    customer_id     UNIQUEIDENTIFIER NULL,                -- optional loyalty link
    subtotal_amount DECIMAL(19,4)    NOT NULL,
    tax_amount      DECIMAL(19,4)    NOT NULL DEFAULT(0),
    total_amount    AS (ROUND(subtotal_amount + tax_amount, 4)) PERSISTED,
    payment_method  VARCHAR(32)      NOT NULL,            -- 'CASH','CARD','WALLET','MIXED'
    is_offline      BIT              NOT NULL DEFAULT(0),
    insert_utc      DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    -- Cluster by store/time to localize writes & enable partitioning
    INDEX CX_pos_txn CLUSTERED (store_id, txn_ts_utc, pos_txn_id) 
        ON ps_txn_month (txn_ts_utc),
    -- Global lookup by ID
    CONSTRAINT UQ_pos_txn_id UNIQUE NONCLUSTERED (pos_txn_id)
);

CREATE TABLE core.pos_txn_line (
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL
        REFERENCES core.pos_txn(pos_txn_id) ON DELETE CASCADE,
    line_no         INT              NOT NULL,
    product_id      BIGINT           NOT NULL REFERENCES core.product(product_id),
    quantity        DECIMAL(18,3)    NOT NULL CHECK (quantity > 0),
    unit_price      DECIMAL(19,4)    NOT NULL,
    discount_amt    DECIMAL(19,4)    NOT NULL DEFAULT(0),
    line_amount     AS (ROUND(quantity * unit_price - discount_amt, 4)) PERSISTED,
    CONSTRAINT PK_pos_txn_line PRIMARY KEY (pos_txn_id, line_no),
    INDEX IX_pos_txn_line_prod (product_id)
);
CREATE TABLE core.pos_payment (
    payment_id      BIGINT          IDENTITY(1,1) PRIMARY KEY,
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL REFERENCES core.pos_txn(pos_txn_id),
    method          VARCHAR(32)     NOT NULL,      -- 'CASH','CARD','WALLET','GIFT'
    amount          DECIMAL(19,4)   NOT NULL,
    auth_code       VARCHAR(64)     NULL,
    provider_ref    VARCHAR(128)    NULL,
    INDEX IX_pos_payment_txn (pos_txn_id)
);

CREATE TABLE core.pos_return (
    return_id       UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL REFERENCES core.pos_txn(pos_txn_id),
    original_txn_id UNIQUEIDENTIFIER NULL,  -- original sale txn
    reason_code     VARCHAR(32)      NULL,  -- 'DEFECT','CUSTOMER','OTHER'
    refund_amount   DECIMAL(19,4)    NOT NULL,
    event_ts_utc    DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE core.inventory_ledger (
    ledger_id      BIGINT          IDENTITY(1,1) NOT NULL,
    store_id       INT             NOT NULL REFERENCES core.store(store_id),
    product_id     BIGINT          NOT NULL REFERENCES core.product(product_id),
    event_ts_utc   DATETIME2(3)    NOT NULL,
    source         VARCHAR(32)     NOT NULL,  -- 'POS','RETURN','RECEIPT','TRANSFER_OUT','TRANSFER_IN','ADJUST'
    reference_id   UNIQUEIDENTIFIER NULL,     -- e.g., pos_txn_id or return_id
    qty_delta      DECIMAL(18,3)   NOT NULL,  -- negative for sale, positive for receipt/return
    note           NVARCHAR(200)   NULL,
    CONSTRAINT PK_inventory_ledger PRIMARY KEY (ledger_id),
    -- Cluster by store/time to partition nicely
    INDEX CX_inventory_ledger CLUSTERED (store_id, event_ts_utc, ledger_id)
        ON ps_txn_month (event_ts_utc),
    INDEX IX_inv_ledger_product (product_id)
);

CREATE TABLE core.stock_receipt (
    receipt_id     UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    store_id       INT              NOT NULL REFERENCES core.store(store_id),
    received_ts_utc DATETIME2(3)    NOT NULL DEFAULT SYSUTCDATETIME(),
    vendor_code    VARCHAR(64)      NULL,
    po_number      VARCHAR(64)      NULL,
    note           NVARCHAR(200)    NULL
);

CREATE TABLE core.stock_receipt_line (
    receipt_id     UNIQUEIDENTIFIER NOT NULL REFERENCES core.stock_receipt(receipt_id) ON DELETE CASCADE,
    line_no        INT              NOT NULL,
    product_id     BIGINT           NOT NULL REFERENCES core.product(product_id),
    qty_received   DECIMAL(18,3)    NOT NULL,
    CONSTRAINT PK_stock_receipt_line PRIMARY KEY (receipt_id, line_no)
);

CREATE TABLE core.stock_transfer (
    transfer_id     UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    src_store_id    INT              NOT NULL REFERENCES core.store(store_id),
    dst_store_id    INT              NOT NULL REFERENCES core.store(store_id),
    shipped_ts_utc  DATETIME2(3)     NULL,
    received_ts_utc DATETIME2(3)     NULL,
    note            NVARCHAR(200)    NULL
);

CREATE TABLE core.stock_transfer_line (
    transfer_id    UNIQUEIDENTIFIER NOT NULL REFERENCES core.stock_transfer(transfer_id) ON DELETE CASCADE,
    line_no        INT              NOT NULL,
    product_id     BIGINT           NOT NULL REFERENCES core.product(product_id),
    qty            DECIMAL(18,3)    NOT NULL CHECK (qty > 0),
    CONSTRAINT PK_stock_transfer_line PRIMARY KEY (transfer_id, line_no)
);

CREATE TABLE core.price_change (
    price_id       BIGINT          IDENTITY(1,1) PRIMARY KEY,
    product_id     BIGINT          NOT NULL REFERENCES core.product(product_id),
    store_id       INT             NULL REFERENCES core.store(store_id), -- NULL = global
    effective_utc  DATETIME2(3)    NOT NULL,
    new_price      DECIMAL(19,4)   NOT NULL
);
CREATE INDEX IX_price_change_product_effective ON core.price_change(product_id, effective_utc DESC);

CREATE TABLE core.promo_applied (
    promo_id       BIGINT          IDENTITY(1,1) PRIMARY KEY,
    pos_txn_id     UNIQUEIDENTIFIER NOT NULL REFERENCES core.pos_txn(pos_txn_id),
    offer_code     VARCHAR(64)     NOT NULL,
    discount_amt   DECIMAL(19,4)   NOT NULL,
    applied_ts_utc DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME()
);
