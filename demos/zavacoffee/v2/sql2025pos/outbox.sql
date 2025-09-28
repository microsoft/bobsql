CREATE TABLE edge.outbox_event (
    event_id        UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_edge_outbox_event_id DEFAULT NEWSEQUENTIALID(),
    event_type      VARCHAR(64)      NOT NULL,  -- 'POS_TXN_CREATED', 'INV_ADJUSTED', ...
    aggregate_id    UNIQUEIDENTIFIER NULL,      -- e.g., pos_txn_id
    store_code      VARCHAR(16)      NOT NULL,
    payload_json    NVARCHAR(MAX)    NOT NULL,  -- denormalized for easy transport
    created_at_utc  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    processed_at_utc DATETIME2(3)    NULL,
    CONSTRAINT PK_edge_outbox_event PRIMARY KEY (event_id),
    INDEX IX_edge_outbox_event_type_created (event_type, created_at_utc)
);