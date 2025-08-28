CREATE OR ALTER PROCEDURE zava.sp_AutoReplenish
  @asof_date DATE = NULL,
  @create_future_receipts BIT = 1
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  IF @asof_date IS NULL SET @asof_date = CAST(GETDATE() AS DATE);

  /* ----------------------------------------------------------
     1) On-hand as-of and reorder candidates (materialized)
     ---------------------------------------------------------- */
  IF OBJECT_ID('tempdb..#OnHand') IS NOT NULL DROP TABLE #OnHand;
  CREATE TABLE #OnHand (
    store_id INT NOT NULL,
    product_id INT NOT NULL,
    on_hand_qty DECIMAL(19,3) NOT NULL,
    PRIMARY KEY (store_id, product_id)
  );

  INSERT INTO #OnHand (store_id, product_id, on_hand_qty)
  SELECT store_id, product_id, SUM(qty) AS on_hand_qty
  FROM zava.InventoryTransaction
  WHERE txn_dt < DATEADD(DAY, 1, @asof_date)
  GROUP BY store_id, product_id;

  /* Candidates: items at/below reorder point.
     If multiple suppliers sell the same product, pick the cheapest (then shortest lead) */
  IF OBJECT_ID('tempdb..#Cand') IS NOT NULL DROP TABLE #Cand;
  CREATE TABLE #Cand (
    store_id INT NOT NULL,
    product_id INT NOT NULL,
    on_hand_qty DECIMAL(19,3) NOT NULL,
    reorder_point DECIMAL(19,3) NOT NULL,
    reorder_qty DECIMAL(19,3) NOT NULL,
    max_stock DECIMAL(19,3) NULL,
    supplier_id INT NOT NULL,
    price_eur DECIMAL(12,2) NOT NULL,
    lead_time_days INT NOT NULL,
    PRIMARY KEY (store_id, product_id)
  );

  ;WITH CandCandidates AS (
    SELECT
      spp.store_id,
      spp.product_id,
      ISNULL(oh.on_hand_qty, 0) AS on_hand_qty,
      spp.reorder_point, spp.reorder_qty, spp.max_stock,
      sp.supplier_id, sp.price_eur, sp.lead_time_days,
      ROW_NUMBER() OVER (
        PARTITION BY spp.store_id, spp.product_id
        ORDER BY sp.price_eur ASC, sp.lead_time_days ASC, sp.supplier_id ASC
      ) AS rn
    FROM zava.StoreProductParam spp
    LEFT JOIN #OnHand oh
      ON oh.store_id = spp.store_id AND oh.product_id = spp.product_id
    JOIN zava.SupplierProduct sp
      ON sp.product_id = spp.product_id
    WHERE ISNULL(oh.on_hand_qty,0) <= spp.reorder_point
  )
  INSERT INTO #Cand (store_id, product_id, on_hand_qty, reorder_point, reorder_qty, max_stock, supplier_id, price_eur, lead_time_days)
  SELECT store_id, product_id, on_hand_qty, reorder_point, reorder_qty, max_stock,
         supplier_id, price_eur, lead_time_days
  FROM CandCandidates
  WHERE rn = 1;  -- pick preferred supplier

  IF NOT EXISTS (SELECT 1 FROM #Cand)
  BEGIN
    -- Nothing to order
    RETURN;
  END

  /* ----------------------------------------------------------
     2) Create PO headers (one per supplier/store), idempotent
     ---------------------------------------------------------- */
  IF OBJECT_ID('tempdb..#HeaderGroups') IS NOT NULL DROP TABLE #HeaderGroups;
  CREATE TABLE #HeaderGroups (
    supplier_id INT NOT NULL,
    store_id INT NOT NULL,
    lead_time_min INT NOT NULL,  -- per group min lead
    PRIMARY KEY (supplier_id, store_id)
  );

  INSERT INTO #HeaderGroups (supplier_id, store_id, lead_time_min)
  SELECT c.supplier_id, c.store_id, MIN(c.lead_time_days) AS lead_time_min
  FROM #Cand c
  GROUP BY c.supplier_id, c.store_id;

  DECLARE @NewPOs TABLE (
    po_id BIGINT PRIMARY KEY,
    supplier_id INT NOT NULL,
    store_id INT NOT NULL
  );

  -- Insert headers only if not already created for this (supplier, store, date)
  INSERT INTO zava.PurchaseOrder (po_number, supplier_id, store_id, order_date, expected_delivery_date, status)
  OUTPUT INSERTED.po_id, INSERTED.supplier_id, INSERTED.store_id INTO @NewPOs(po_id, supplier_id, store_id)
  SELECT
    CONCAT('PO-', NEXT VALUE FOR zava.seq_po_number),
    hg.supplier_id,
    hg.store_id,
    @asof_date,
    DATEADD(DAY, hg.lead_time_min, @asof_date),
    'APPROVED'
  FROM #HeaderGroups hg
  WHERE NOT EXISTS (
    SELECT 1
    FROM zava.PurchaseOrder po
    WHERE po.supplier_id = hg.supplier_id
      AND po.store_id    = hg.store_id
      AND po.order_date  = @asof_date
  );

  -- If headers already existed (e.g., rerun), include them in @NewPOs so lines can be (re)inserted idempotently
  INSERT INTO @NewPOs (po_id, supplier_id, store_id)
  SELECT po.po_id, po.supplier_id, po.store_id
  FROM zava.PurchaseOrder po
  JOIN #HeaderGroups hg
    ON hg.supplier_id = po.supplier_id AND hg.store_id = po.store_id
  WHERE po.order_date = @asof_date
    AND NOT EXISTS (SELECT 1 FROM @NewPOs x WHERE x.po_id = po.po_id);

  /* ----------------------------------------------------------
     3) Insert PO lines for candidates (one line per SKU)
         - Avoid duplicate lines if rerun for the same PO
     ---------------------------------------------------------- */
  INSERT INTO zava.PurchaseOrderLine (po_id, product_id, qty_ordered, unit_price_eur)
  SELECT npo.po_id, c.product_id, c.reorder_qty, c.price_eur
  FROM @NewPOs npo
  JOIN #Cand c
    ON c.supplier_id = npo.supplier_id AND c.store_id = npo.store_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM zava.PurchaseOrderLine pol
    WHERE pol.po_id = npo.po_id
      AND pol.product_id = c.product_id
  );

  /* ----------------------------------------------------------
     4) Update PO totals for newly affected POs
     ---------------------------------------------------------- */
  UPDATE p
  SET total_amount_eur = x.total_amount
  FROM zava.PurchaseOrder p
  JOIN (
      SELECT po_id, SUM(line_amount_eur) AS total_amount
      FROM zava.PurchaseOrderLine
      WHERE po_id IN (SELECT po_id FROM @NewPOs)
      GROUP BY po_id
  ) x ON x.po_id = p.po_id;

  /* ----------------------------------------------------------
     5) (Optional) Create future RECEIPT transactions
        Note: If you use Shipment/Delivery, set @create_future_receipts = 0
     ---------------------------------------------------------- */
  IF @create_future_receipts = 1
  BEGIN
    INSERT INTO zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference)
    SELECT p.store_id, pol.product_id, 'RECEIPT',
           pol.qty_ordered,
           CAST(p.expected_delivery_date AS DATETIME2(0)),
           CONCAT('PO-RECEIPT:', p.po_number)
    FROM zava.PurchaseOrder p
    JOIN zava.PurchaseOrderLine pol ON pol.po_id = p.po_id
    WHERE p.po_id IN (SELECT po_id FROM @NewPOs);
  END
END
GO
