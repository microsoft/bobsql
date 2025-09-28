-- Option A

CREATE SCHEMA ingest AUTHORIZATION dbo;

CREATE TABLE ingest.pos_txn_inbox
(
    inbox_id       BIGINT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    store_code     VARCHAR(16)      NOT NULL,
    payload_json   NVARCHAR(MAX)    NOT NULL,     -- header + lines + payments + promos
    received_utc   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    status         TINYINT          NOT NULL DEFAULT(0), -- 0=new,1=processing,2=done,3=error
    processed_utc  DATETIME2(3)     NULL,
    error_msg      NVARCHAR(4000)   NULL
);
CREATE INDEX IX_inbox_status ON ingest.pos_txn_inbox(status, inbox_id);
CREATE INDEX IX_inbox_received ON ingest.pos_txn_inbox(received_utc);

CREATE OR ALTER PROCEDURE ingest.apply_pos_inbox_batch
    @batch_size INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 1) Claim a batch cooperatively
    DECLARE @claimed TABLE (inbox_id BIGINT PRIMARY KEY);

    ;WITH cte AS (
        SELECT TOP (@batch_size) inbox_id
        FROM ingest.pos_txn_inbox WITH (READPAST)
        WHERE status = 0
        ORDER BY inbox_id
    )
    UPDATE i WITH (ROWLOCK)
       SET status = 1
     OUTPUT inserted.inbox_id INTO @claimed(inbox_id)
    FROM ingest.pos_txn_inbox i
    JOIN cte ON cte.inbox_id = i.inbox_id;

    IF NOT EXISTS (SELECT 1 FROM @claimed) RETURN;

    BEGIN TRY
        ;WITH payloads AS (
          SELECT i.inbox_id, i.store_code, i.payload_json
          FROM ingest.pos_txn_inbox i
          JOIN @claimed c ON c.inbox_id = i.inbox_id
        ),
        header AS (
          SELECT 
            p.inbox_id, p.store_code,
            jh.pos_txn_id, jh.terminal_code,
            CONVERT(date, jh.business_date)     AS business_date,
            CONVERT(datetime2(3), jh.txn_ts_utc) AS txn_ts_utc,
            TRY_CONVERT(uniqueidentifier, jh.customer_id) AS customer_id,
            CONVERT(decimal(19,4), jh.subtotal_amount) AS subtotal_amount,
            CONVERT(decimal(19,4), jh.tax_amount)      AS tax_amount,
            jh.payment_method,
            CONVERT(bit, jh.is_offline) AS is_offline
          FROM payloads p
          CROSS APPLY OPENJSON(p.payload_json, '$.pos_txn')
            WITH (
              pos_txn_id       uniqueidentifier '$.pos_txn_id',
              terminal_code    varchar(32)      '$.terminal_code',
              business_date    nvarchar(30)     '$.business_date',
              txn_ts_utc       nvarchar(40)     '$.txn_ts_utc',
              customer_id      nvarchar(50)     '$.customer_id',
              subtotal_amount  decimal(19,4)    '$.subtotal_amount',
              tax_amount       decimal(19,4)    '$.tax_amount',
              payment_method   varchar(32)      '$.payment_method',
              is_offline       bit              '$.is_offline'
            ) jh
        ),
        lines AS (
          SELECT p.inbox_id, jl.line_no, jl.product_sku,
                 CONVERT(decimal(18,3), jl.quantity)    AS quantity,
                 CONVERT(decimal(19,4), jl.unit_price)  AS unit_price,
                 CONVERT(decimal(19,4), jl.discount_amt) AS discount_amt
          FROM payloads p
          CROSS APPLY OPENJSON(p.payload_json, '$.lines')
            WITH (
              line_no     int           '$.line_no',
              product_sku varchar(64)   '$.product_sku',
              quantity    decimal(18,3) '$.quantity',
              unit_price  decimal(19,4) '$.unit_price',
              discount_amt decimal(19,4) '$.discount_amt'
            ) jl
        ),
        pays AS (
          SELECT p.inbox_id, jp.[method], CONVERT(decimal(19,4), jp.amount) AS amount,
                 jp.auth_code, jp.provider_ref
          FROM payloads p
          CROSS APPLY OPENJSON(p.payload_json, '$.payments')
            WITH (
              method       varchar(32)   '$.method',
              amount       decimal(19,4) '$.amount',
              auth_code    varchar(64)   '$.auth_code',
              provider_ref varchar(128)  '$.provider_ref'
            ) jp
        ),
        promos AS (
          SELECT p.inbox_id, jx.offer_code, CONVERT(decimal(19,4), jx.discount_amt) AS discount_amt
          FROM payloads p
          CROSS APPLY OPENJSON(p.payload_json, '$.promos')
            WITH (
              offer_code   varchar(64)   '$.offer_code',
              discount_amt decimal(19,4) '$.discount_amt'
            ) jx
        )
        -- 2) Upserts (idempotent)
        INSERT INTO core.pos_txn (pos_txn_id, store_id, terminal_code, business_date, txn_ts_utc, customer_id,
                                  subtotal_amount, tax_amount, payment_method, is_offline)
        SELECT h.pos_txn_id, s.store_id, h.terminal_code, h.business_date, h.txn_ts_utc, h.customer_id,
               h.subtotal_amount, h.tax_amount, h.payment_method, h.is_offline
        FROM header h
        JOIN core.store s ON s.store_code = h.store_code
        WHERE NOT EXISTS (SELECT 1 FROM core.pos_txn t WHERE t.pos_txn_id = h.pos_txn_id);

        INSERT INTO core.pos_txn_line (pos_txn_id, line_no, product_id, quantity, unit_price, discount_amt)
        SELECT h.pos_txn_id, l.line_no, p.product_id, l.quantity, l.unit_price, l.discount_amt
        FROM lines l
        JOIN header h   ON h.inbox_id = l.inbox_id
        JOIN core.product p ON p.product_sku = l.product_sku
        WHERE NOT EXISTS (
            SELECT 1 FROM core.pos_txn_line x
            WHERE x.pos_txn_id = h.pos_txn_id AND x.line_no = l.line_no
        );

        INSERT INTO core.pos_payment (pos_txn_id, method, amount, auth_code, provider_ref)
        SELECT h.pos_txn_id, pay.method, pay.amount, pay.auth_code, pay.provider_ref
        FROM pays pay
        JOIN header h ON h.inbox_id = pay.inbox_id;

        INSERT INTO core.promo_applied (pos_txn_id, offer_code, discount_amt)
        SELECT h.pos_txn_id, pr.offer_code, pr.discount_amt
        FROM promos pr
        JOIN header h ON h.inbox_id = pr.inbox_id;

        -- Inventory ledger entries for sales (negative deltas)
        INSERT INTO core.inventory_ledger (store_id, product_id, event_ts_utc, source, reference_id, qty_delta, note)
        SELECT s.store_id, p.product_id, h.txn_ts_utc, 'POS', h.pos_txn_id, -l.quantity, NULL
        FROM lines l
        JOIN header h   ON h.inbox_id = l.inbox_id
        JOIN core.store s ON s.store_code = h.store_code
        JOIN core.product p ON p.product_sku = l.product_sku;

        -- 3) Mark done
        UPDATE i
           SET status = 2, processed_utc = SYSUTCDATETIME(), error_msg = NULL
        FROM ingest.pos_txn_inbox i
        JOIN @claimed c ON c.inbox_id = i.inbox_id;
    END TRY
    BEGIN CATCH
        UPDATE i
           SET status = 3, processed_utc = SYSUTCDATETIME(),
               error_msg = CONCAT(ERROR_NUMBER(), ': ', LEFT(ERROR_MESSAGE(), 3800))
        FROM ingest.pos_txn_inbox i
        JOIN @claimed c ON c.inbox_id = i.inbox_id;
        THROW;
    END CATCH


-- Option B

CREATE TYPE tvp_pos_txn_header AS TABLE
(
    pos_txn_id       UNIQUEIDENTIFIER NOT NULL,
    store_code       VARCHAR(16)      NOT NULL,
    terminal_code    VARCHAR(32)      NOT NULL,
    business_date    DATE             NOT NULL,
    txn_ts_utc       DATETIME2(3)     NOT NULL,
    customer_id      UNIQUEIDENTIFIER NULL,
    subtotal_amount  DECIMAL(19,4)    NOT NULL,
    tax_amount       DECIMAL(19,4)    NOT NULL,
    payment_method   VARCHAR(32)      NOT NULL,
    is_offline       BIT              NOT NULL
);

CREATE TYPE tvp_pos_txn_line AS TABLE
(
    pos_txn_id    UNIQUEIDENTIFIER NOT NULL,
    line_no       INT              NOT NULL,
    product_sku   VARCHAR(64)      NOT NULL,
    quantity      DECIMAL(18,3)    NOT NULL,
    unit_price    DECIMAL(19,4)    NOT NULL,
    discount_amt  DECIMAL(19,4)    NOT NULL
);

CREATE TYPE tvp_pos_payment AS TABLE
(
    pos_txn_id    UNIQUEIDENTIFIER NOT NULL,
    method        VARCHAR(32)      NOT NULL,
    amount        DECIMAL(19,4)    NOT NULL,
    auth_code     VARCHAR(64)      NULL,
    provider_ref  VARCHAR(128)     NULL
);

CREATE TYPE tvp_pos_promo AS TABLE
(
    pos_txn_id    UNIQUEIDENTIFIER NOT NULL,
    offer_code    VARCHAR(64)      NOT NULL,
    discount_amt  DECIMAL(19,4)    NOT NULL
);

CREATE OR ALTER PROCEDURE ingest.upsert_pos_txn_batch_tvp
    @hdr tvp_pos_txn_header READONLY,
    @lns tvp_pos_txn_line   READONLY,
    @pays tvp_pos_payment   READONLY,
    @prom tvp_pos_promo     READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Headers (idempotent insert)
    INSERT INTO core.pos_txn (pos_txn_id, store_id, terminal_code, business_date, txn_ts_utc, customer_id,
                              subtotal_amount, tax_amount, payment_method, is_offline)
    SELECT h.pos_txn_id, s.store_id, h.terminal_code, h.business_date, h.txn_ts_utc, h.customer_id,
           h.subtotal_amount, h.tax_amount, h.payment_method, h.is_offline
    FROM @hdr h
    JOIN core.store s ON s.store_code = h.store_code
    WHERE NOT EXISTS (SELECT 1 FROM core.pos_txn t WHERE t.pos_txn_id = h.pos_txn_id);

    -- Lines
    INSERT INTO core.pos_txn_line (pos_txn_id, line_no, product_id, quantity, unit_price, discount_amt)
    SELECT l.pos_txn_id, l.line_no, p.product_id, l.quantity, l.unit_price, l.discount_amt
    FROM @lns l
    JOIN core.product p ON p.product_sku = l.product_sku
    WHERE NOT EXISTS (
        SELECT 1 FROM core.pos_txn_line x
        WHERE x.pos_txn_id = l.pos_txn_id AND x.line_no = l.line_no
    );

    -- Payments
    INSERT INTO core.pos_payment (pos_txn_id, method, amount, auth_code, provider_ref)
    SELECT pos_txn_id, method, amount, auth_code, provider_ref
    FROM @pays;

    -- Promos
    INSERT INTO core.promo_applied (pos_txn_id, offer_code, discount_amt)
    SELECT pos_txn_id, offer_code, discount_amt
    FROM @prom;

    -- Inventory ledger entries for sales
    INSERT INTO core.inventory_ledger (store_id, product_id, event_ts_utc, source, reference_id, qty_delta, note)
    SELECT s.store_id, p.product_id, h.txn_ts_utc, 'POS', h.pos_txn_id, -l.quantity, NULL
    FROM @lns l
    JOIN @hdr h ON h.pos_txn_id = l.pos_txn_id
    JOIN core.store s ON s.store_code = h.store_code
    JOIN core.product p ON p.product_sku = l.product_sku;
END
