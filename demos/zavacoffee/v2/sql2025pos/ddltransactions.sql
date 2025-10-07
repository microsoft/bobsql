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