-- Store & terminal catalog (small, cached)
CREATE TABLE edge.store (
    store_id        INT            IDENTITY(1,1) PRIMARY KEY,
    store_code      VARCHAR(16)    NOT NULL UNIQUE, -- aligns with HQ & Fabric
    store_name      NVARCHAR(200)  NOT NULL,
    time_zone       VARCHAR(64)    NOT NULL,
    is_active       BIT            NOT NULL DEFAULT(1)
);

CREATE TABLE edge.pos_terminal (
    terminal_id     INT           IDENTITY(1,1) PRIMARY KEY,
    store_id        INT           NOT NULL
        REFERENCES edge.store(store_id),
    terminal_code   VARCHAR(32)   NOT NULL,
    is_active       BIT           NOT NULL DEFAULT(1),
    UNIQUE (store_id, terminal_code)
);

-- Product catalog (replicated from HQ), priced for store
CREATE TABLE edge.product (
    product_id      BIGINT         NOT NULL,        -- assigned by HQ
    product_sku     VARCHAR(64)    NOT NULL,        -- business key
    product_name    NVARCHAR(300)  NOT NULL,
    category        NVARCHAR(200)  NULL,
    list_price      DECIMAL(19,4)  NOT NULL,
    tax_rate        DECIMAL(9,4)   NOT NULL DEFAULT(0),
    is_active       BIT            NOT NULL DEFAULT(1),
    CONSTRAINT PK_edge_product PRIMARY KEY (product_id),
    CONSTRAINT UQ_edge_product_sku UNIQUE (product_sku)
);

-- Current on-hand inventory per store
CREATE TABLE edge.inventory (
    store_id        INT            NOT NULL
        REFERENCES edge.store(store_id),
    product_id      BIGINT         NOT NULL
        REFERENCES edge.product(product_id),
    on_hand_qty     DECIMAL(18,3)  NOT NULL DEFAULT(0),
    last_updated_at DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_edge_inventory PRIMARY KEY (store_id, product_id)
);

-- POS transaction header
CREATE TABLE edge.pos_txn (
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_edge_pos_txn_id DEFAULT NEWSEQUENTIALID(),
    store_id        INT              NOT NULL
        REFERENCES edge.store(store_id),
    terminal_id     INT              NOT NULL
        REFERENCES edge.pos_terminal(terminal_id),
    business_date   DATE             NOT NULL,              -- local store date
    txn_ts_utc      DATETIME2(3)     NOT NULL,              -- capture time
    customer_id     UNIQUEIDENTIFIER NULL,                  -- optional (loyalty link)
    total_amount    DECIMAL(19,4)    NOT NULL,
    payment_method  VARCHAR(32)      NOT NULL,              -- 'CASH','CARD',...
    is_offline      BIT              NOT NULL DEFAULT(0),   -- if processed offline
    CONSTRAINT PK_edge_pos_txn PRIMARY KEY (pos_txn_id),
    INDEX IX_edge_pos_txn_store_date (store_id, business_date, txn_ts_utc)
);

-- POS transaction lines
CREATE TABLE edge.pos_txn_line (
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL
        REFERENCES edge.pos_txn(pos_txn_id),
    line_no         INT              NOT NULL,
    product_id      BIGINT           NOT NULL
        REFERENCES edge.product(product_id),
    quantity        DECIMAL(18,3)    NOT NULL CHECK (quantity > 0),
    unit_price      DECIMAL(19,4)    NOT NULL,
    line_amount     AS (ROUND(quantity * unit_price, 4)) PERSISTED,
    CONSTRAINT PK_edge_pos_txn_line PRIMARY KEY (pos_txn_id, line_no),
    INDEX IX_edge_pos_txn_line_prod (product_id)
);

-- Product description embeddings for vector search at the edge
CREATE TABLE edge.product_embedding (
    embedding_id     UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_edge_embedding_id DEFAULT NEWSEQUENTIALID(),
    product_id       BIGINT           NOT NULL 
        REFERENCES edge.product(product_id),
    embedding        VARBINARY(MAX)   NOT NULL,    -- raw float32 bytes or packed
    embedding_dim    INT              NOT NULL,    -- e.g., 1024, 1536
    embedding_model  NVARCHAR(100)    NOT NULL,    -- 'mxbai-embed-large'
    created_at_utc   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_edge_product_embedding PRIMARY KEY (embedding_id),
    UNIQUE (product_id, embedding_model) -- one model/version per product
);

-- Optional: Local model registry (for demo transparency)
CREATE TABLE edge.local_ai_model (
    model_name      NVARCHAR(100) NOT NULL PRIMARY KEY, -- 'mxbai-embed-large'
    provider        NVARCHAR(50)  NOT NULL,             -- 'ollama'
    model_version   NVARCHAR(50)  NULL,
    params_json     NVARCHAR(MAX) NULL,
    installed_at    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
