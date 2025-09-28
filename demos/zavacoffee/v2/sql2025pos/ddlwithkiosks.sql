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
CREATE TABLE edge.store (
    store_id        INT            IDENTITY(1,1) PRIMARY KEY,
    store_code      VARCHAR(16)    NOT NULL UNIQUE,
    store_name      NVARCHAR(200)  NOT NULL,
    time_zone       VARCHAR(64)    NOT NULL,
    is_active       BIT            NOT NULL DEFAULT(1)
);

-- POS terminals (supports KIOSK vs REGISTER vs MOBILE)
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
CREATE INDEX IX_pos_terminal_type ON edge.pos_terminal (terminal_type);

-- Product catalog (assigned by HQ; not identity here)
CREATE TABLE edge.product (
    product_id      BIGINT         NOT NULL,          -- stable HQ ID
    product_sku     VARCHAR(64)    NOT NULL,
    product_name    NVARCHAR(300)  NOT NULL,
    category        NVARCHAR(200)  NULL,
    list_price      DECIMAL(19,4)  NOT NULL,
    tax_rate        DECIMAL(9,4)   NOT NULL DEFAULT(0),
    is_active       BIT            NOT NULL DEFAULT(1),
    CONSTRAINT PK_edge_product PRIMARY KEY (product_id),
    CONSTRAINT UQ_edge_product_sku UNIQUE (product_sku)
);

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

/* ------------------------------
   2) POS transactions
   ------------------------------ */

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
    subtotal_amount DECIMAL(19,4)    NULL,                  -- optional snapshot
    tax_amount      DECIMAL(19,4)    NULL,
    total_amount    DECIMAL(19,4)    NOT NULL,              -- final amount
    payment_method  VARCHAR(32)      NOT NULL,              -- 'CASH','CARD','WALLET','MIXED'
    is_offline      BIT              NOT NULL DEFAULT(0),   -- if processed offline
    CONSTRAINT PK_edge_pos_txn PRIMARY KEY (pos_txn_id)
);
CREATE INDEX IX_edge_pos_txn_store_date 
    ON edge.pos_txn (store_id, business_date, txn_ts_utc);

-- POS transaction lines
CREATE TABLE edge.pos_txn_line (
    pos_txn_id      UNIQUEIDENTIFIER NOT NULL
        REFERENCES edge.pos_txn(pos_txn_id) ON DELETE CASCADE,
    line_no         INT              NOT NULL,
    product_id      BIGINT           NOT NULL
        REFERENCES edge.product(product_id),
    quantity        DECIMAL(18,3)    NOT NULL CHECK (quantity > 0),
    unit_price      DECIMAL(19,4)    NOT NULL,
    discount_amt    DECIMAL(19,4)    NOT NULL DEFAULT(0),
    line_amount     AS (ROUND(quantity * unit_price - discount_amt, 4)) PERSISTED,
    CONSTRAINT PK_edge_pos_txn_line PRIMARY KEY (pos_txn_id, line_no)
);
CREATE INDEX IX_edge_pos_txn_line_prod ON edge.pos_txn_line (product_id);

/* ------------------------------
   3) Vector search assets (edge)
   ------------------------------ */

-- Product description embeddings for vector search at the edge
-- Supports production (VARBINARY) and pure SQL demo (JSON) paths
CREATE TABLE edge.product_embedding (
    embedding_id     UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_edge_embedding_id DEFAULT NEWSEQUENTIALID(),
    product_id       BIGINT           NOT NULL 
        REFERENCES edge.product(product_id),
    embedding        VARBINARY(MAX)   NULL,    -- raw float32 bytes or packed
    embedding_json   NVARCHAR(MAX)    NULL,    -- JSON array of floats for T-SQL demo
    embedding_dim    INT              NULL,    -- e.g., 64/128 for demo; 1024/1536 for prod
    embedding_model  NVARCHAR(100)    NULL,    -- 'mxbai-embed-large'
    created_at_utc   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_edge_product_embedding PRIMARY KEY (embedding_id),
    CONSTRAINT UQ_edge_product_embedding UNIQUE (product_id, embedding_model)
);
CREATE INDEX IX_edge_product_embedding_prod ON edge.product_embedding(product_id);

-- Optional: Local model registry (for transparency)
CREATE TABLE edge.local_ai_model (
    model_name      NVARCHAR(100) NOT NULL PRIMARY KEY, -- 'mxbai-embed-large'
    provider        NVARCHAR(50)  NOT NULL,             -- 'ollama'
    model_version   NVARCHAR(50)  NULL,
    params_json     NVARCHAR(MAX) NULL,
    installed_at    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);

/* ------------------------------
   4) Self-serve kiosk: sessions, basket, events, search logs
   ------------------------------ */

-- Kiosk session (ties to a kiosk terminal and store)
CREATE TABLE edge.kiosk_session (
    session_id      UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_kiosk_session_id DEFAULT NEWSEQUENTIALID(),
    store_id        INT              NOT NULL 
        REFERENCES edge.store(store_id),
    terminal_id     INT              NOT NULL 
        REFERENCES edge.pos_terminal(terminal_id),
    customer_id     UNIQUEIDENTIFIER NULL,         -- optional loyalty
    started_at_utc  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    ended_at_utc    DATETIME2(3)     NULL,
    status          VARCHAR(16)      NOT NULL DEFAULT('ACTIVE') 
        CHECK (status IN ('ACTIVE','ABANDONED','CHECKED_OUT','CANCELLED')),
    CONSTRAINT PK_kiosk_session PRIMARY KEY (session_id)
);
CREATE INDEX IX_kiosk_session_store_start 
    ON edge.kiosk_session (store_id, started_at_utc);
CREATE INDEX IX_kiosk_session_terminal 
    ON edge.kiosk_session (terminal_id, status);

-- Basket items per kiosk session
CREATE TABLE edge.kiosk_basket_item (
    session_id      UNIQUEIDENTIFIER NOT NULL 
        REFERENCES edge.kiosk_session(session_id) ON DELETE CASCADE,
    line_no         INT              NOT NULL,
    product_id      BIGINT           NOT NULL 
        REFERENCES edge.product(product_id),
    quantity        DECIMAL(18,3)    NOT NULL CHECK (quantity > 0),
    unit_price      DECIMAL(19,4)    NOT NULL,   -- snapshot price at add time
    discount_amt    DECIMAL(19,4)    NOT NULL DEFAULT(0),
    line_amount     AS (ROUND(quantity * unit_price - discount_amt, 4)) PERSISTED,
    CONSTRAINT PK_kiosk_basket_item PRIMARY KEY (session_id, line_no)
);
CREATE INDEX IX_kiosk_basket_product ON edge.kiosk_basket_item(product_id);

-- UX events/telemetry (search, view, add, etc.)
CREATE TABLE edge.kiosk_event (
    event_id        BIGINT           IDENTITY(1,1) PRIMARY KEY,
    session_id      UNIQUEIDENTIFIER NOT NULL 
        REFERENCES edge.kiosk_session(session_id) ON DELETE CASCADE,
    event_ts_utc    DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    event_type      VARCHAR(32)      NOT NULL, -- 'SEARCH','ADD_TO_CART','REMOVE','VIEW','CHECKOUT_*'
    payload_json    NVARCHAR(MAX)    NULL
);
CREATE INDEX IX_kiosk_event_session_time 
    ON edge.kiosk_event(session_id, event_ts_utc);

-- Logged search query (text + embedding + metadata)
CREATE TABLE edge.kiosk_search_query (
    query_id        UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_kiosk_query_id DEFAULT NEWSEQUENTIALID(),
    session_id      UNIQUEIDENTIFIER NOT NULL 
        REFERENCES edge.kiosk_session(session_id) ON DELETE CASCADE,
    query_text      NVARCHAR(4000)   NULL,            -- user text (optional)
    embedding       VARBINARY(MAX)   NULL,            -- production path
    embedding_json  NVARCHAR(MAX)    NULL,            -- T-SQL demo path
    embedding_dim   INT              NULL,
    embedding_model NVARCHAR(100)    NULL,            -- 'mxbai-embed-large'
    top_k           INT              NOT NULL DEFAULT(10),
    latency_ms      INT              NULL,            -- measured by app or SQL demo
    created_at_utc  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_kiosk_search_query PRIMARY KEY (query_id)
);
CREATE INDEX IX_kiosk_search_session 
    ON edge.kiosk_search_query(session_id, created_at_utc DESC);

-- Search results (top-k ranking stored)
CREATE TABLE edge.kiosk_search_result (
    query_id        UNIQUEIDENTIFIER NOT NULL 
        REFERENCES edge.kiosk_search_query(query_id) ON DELETE CASCADE,
    rank_no         INT              NOT NULL,
    product_id      BIGINT           NOT NULL 
        REFERENCES edge.product(product_id),
    score           FLOAT            NOT NULL,        -- cosine similarity or dot product
    was_selected    BIT              NOT NULL DEFAULT(0),
    CONSTRAINT PK_kiosk_search_result PRIMARY KEY (query_id, rank_no)
);
CREATE INDEX IX_kiosk_search_product ON edge.kiosk_search_result(product_id);

/* ------------------------------
   5) Outbox (offline → HQ)
   ------------------------------ */

-- Transactional outbox for offline sync to HQ
CREATE TABLE edge.outbox_event (
    event_id         UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_edge_outbox_event_id DEFAULT NEWSEQUENTIALID(),
    event_type       VARCHAR(64)      NOT NULL,      -- 'POS_TXN_CREATED','INV_ADJUSTED',...
    aggregate_id     UNIQUEIDENTIFIER NULL,          -- e.g., pos_txn_id
    store_code       VARCHAR(16)      NOT NULL,
    payload_json     NVARCHAR(MAX)    NOT NULL,      -- denormalized for easy transport
    created_at_utc   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    processed_at_utc DATETIME2(3)     NULL,
    CONSTRAINT PK_edge_outbox_event PRIMARY KEY (event_id)
);
CREATE INDEX IX_edge_outbox_event_type_created 
    ON edge.outbox_event(event_type, created_at_utc);