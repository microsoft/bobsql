CREATE OR ALTER PROCEDURE edge.kiosk_checkout_prod
    @session_id     UNIQUEIDENTIFIER,
    @payment_method VARCHAR(32) = 'CARD',
    @pos_txn_id     UNIQUEIDENTIFIER = NULL OUTPUT  -- pass a value for idempotency; returns final id
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @store_id INT, @terminal_id INT, @tz VARCHAR(64), @customer_id UNIQUEIDENTIFIER;

    SELECT @store_id = s.store_id,
           @terminal_id = ks.terminal_id,
           @tz = st.time_zone,
           @customer_id = ks.customer_id
    FROM edge.kiosk_session ks
    JOIN edge.store st ON st.store_id = ks.store_id
    WHERE ks.session_id = @session_id AND ks.status = 'ACTIVE';

    IF @store_id IS NULL
        THROW 51050, 'Session not found or not ACTIVE.', 1;

    -- Compute totals
    ;WITH l AS (
      SELECT kbi.product_id, kbi.quantity, kbi.unit_price, kbi.discount_amt,
             ROUND(kbi.quantity * kbi.unit_price - kbi.discount_amt, 4) AS line_amount
      FROM edge.kiosk_basket_item kbi
      WHERE kbi.session_id = @session_id
    )
    SELECT 
      CAST(SUM(l.line_amount) AS DECIMAL(19,4)) AS subtotal,
      CAST(SUM(ROUND(l.line_amount * p.tax_rate, 4)) AS DECIMAL(19,4)) AS tax
    INTO #totals
    FROM l
    JOIN edge.product p ON p.product_id = l.product_id;

    IF NOT EXISTS (SELECT 1 FROM edge.kiosk_basket_item WHERE session_id = @session_id)
        THROW 51051, 'Basket is empty.', 1;

    DECLARE @subtotal DECIMAL(19,4), @tax DECIMAL(19,4), @total DECIMAL(19,4);
    SELECT @subtotal = ISNULL(subtotal, 0), @tax = ISNULL(tax, 0) FROM #totals;
    SET @total = ROUND(@subtotal + @tax, 4);

    -- Local business date
    DECLARE @business_date DATE = CONVERT(date, (SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @tz);

    -- Prepare an aggregated requirement per product for inventory check
    IF OBJECT_ID('tempdb..#req') IS NOT NULL DROP TABLE #req;
    SELECT kbi.product_id, SUM(kbi.quantity) AS qty_req
    INTO #req
    FROM edge.kiosk_basket_item kbi
    WHERE kbi.session_id = @session_id
    GROUP BY kbi.product_id;

    -- Validate stock availability set-based
    ;WITH inv AS (
      SELECT i.product_id, i.on_hand_qty
      FROM edge.inventory i
      WHERE i.store_id = @store_id
    )
    SELECT r.product_id, r.qty_req, inv.on_hand_qty
    INTO #insufficient
    FROM #req r
    LEFT JOIN inv ON inv.product_id = r.product_id
    WHERE inv.on_hand_qty IS NULL OR inv.on_hand_qty < r.qty_req;

    IF EXISTS (SELECT 1 FROM #insufficient)
    BEGIN
        -- Return which SKUs failed
        SELECT p.product_sku, p.product_name, i.qty_req, i.on_hand_qty
        FROM #insufficient i
        JOIN edge.product p ON p.product_id = i.product_id;
        THROW 51052, 'Insufficient inventory for one or more items.', 1;
    END

    -- Idempotent POS txn id
    IF @pos_txn_id IS NULL SET @pos_txn_id = NEWSEQUENTIALID();

    BEGIN TRAN;

      -- Insert header if not exists
      IF NOT EXISTS (SELECT 1 FROM edge.pos_txn WHERE pos_txn_id = @pos_txn_id)
      BEGIN
        INSERT INTO edge.pos_txn
          (pos_txn_id, store_id, terminal_id, business_date, txn_ts_utc, customer_id,
           subtotal_amount, tax_amount, total_amount, payment_method, is_offline)
        VALUES
          (@pos_txn_id, @store_id, @terminal_id, @business_date, SYSUTCDATETIME(), @customer_id,
           @subtotal, @tax, @total, @payment_method, 1);
      END

      -- Insert lines idempotently
      INSERT INTO edge.pos_txn_line (pos_txn_id, line_no, product_id, quantity, unit_price, discount_amt)
      SELECT @pos_txn_id,
             ROW_NUMBER() OVER (ORDER BY kbi.line_no),
             kbi.product_id, kbi.quantity, kbi.unit_price, kbi.discount_amt
      FROM edge.kiosk_basket_item kbi
      WHERE kbi.session_id = @session_id
      AND NOT EXISTS (
        SELECT 1 FROM edge.pos_txn_line x 
        WHERE x.pos_txn_id = @pos_txn_id AND x.line_no = kbi.line_no
      );

      -- Atomic decrement: set-based update using aggregated requirement
      UPDATE i
         SET i.on_hand_qty = i.on_hand_qty - r.qty_req,
             i.last_updated_at = SYSUTCDATETIME()
      FROM edge.inventory i
      JOIN #req r ON r.product_id = i.product_id
      WHERE i.store_id = @store_id;

      -- Emit outbox event (compact payload with header + lines)
      DECLARE @store_code VARCHAR(16);
      SELECT @store_code = s.store_code FROM edge.store s WHERE s.store_id = @store_id;

      INSERT INTO edge.outbox_event (event_type, aggregate_id, store_code, payload_json)
      SELECT 'POS_TXN_CREATED', @pos_txn_id, @store_code,
             (
               SELECT
                 @pos_txn_id      AS pos_txn_id,
                 @store_code      AS store_code,
                 @payment_method  AS payment_method,
                 @subtotal        AS subtotal_amount,
                 @tax             AS tax_amount,
                 @total           AS total_amount,
                 (SELECT product_id, quantity, unit_price, discount_amt
                  FROM edge.pos_txn_line
                  WHERE pos_txn_id = @pos_txn_id
                  ORDER BY line_no
                  FOR JSON PATH) AS lines
               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
             );

      -- Close session and clear basket
      UPDATE edge.kiosk_session
         SET status = 'CHECKED_OUT', ended_at_utc = SYSUTCDATETIME()
       WHERE session_id = @session_id AND status = 'ACTIVE';

      DELETE FROM edge.kiosk_basket_item WHERE session_id = @session_id;

      INSERT INTO edge.kiosk_event (session_id, event_type, payload_json)
      VALUES (@session_id, 'CHECKOUT_COMPLETED',
              CONCAT(N'{"pos_txn_id":"', CONVERT(VARCHAR(36), @pos_txn_id), '"}'));

    COMMIT TRAN;

    -- Return the final POS txn
    SELECT t.pos_txn_id, t.store_id, t.terminal_id, t.business_date, t.txn_ts_utc, 
           t.subtotal_amount, t.tax_amount, t.total_amount, t.payment_method, t.is_offline
    FROM edge.pos_txn t
    WHERE t.pos_txn_id = @pos_txn_id;

    -- And the lines
    SELECT l.pos_txn_id, l.line_no, p.product_sku, p.product_name, l.quantity, l.unit_price, l.discount_amt, l.line_amount
    FROM edge.pos_txn_line l
    JOIN edge.product p ON p.product_id = l.product_id
    WHERE l.pos_txn_id = @pos_txn_id
    ORDER BY l.line_no;
END
