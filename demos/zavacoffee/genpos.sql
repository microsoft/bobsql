------------------------------------------------------------
-- Proc: generate POs for items below reorder point
------------------------------------------------------------
CREATE OR ALTER PROCEDURE zava.sp_AutoReplenish
  @asof_date DATE = NULL,
  @create_future_receipts BIT = 1
AS
BEGIN
  SET NOCOUNT ON;
  IF @asof_date IS NULL SET @asof_date = CAST(GETDATE() AS DATE);

  -- On-hand as of @asof_date
  ;WITH OnHand AS (
    SELECT store_id, product_id, SUM(qty) AS on_hand_qty
    FROM zava.InventoryTransaction
    WHERE txn_dt < DATEADD(DAY,1,@asof_date)
    GROUP BY store_id, product_id
  ),
  Cand AS (
    SELECT spp.store_id, spp.product_id,
           ISNULL(oh.on_hand_qty,0) AS on_hand_qty,
           spp.reorder_point, spp.reorder_qty, spp.max_stock,
           sp.supplier_id, sp.price_eur, sp.lead_time_days
    FROM zava.StoreProductParam spp
    LEFT JOIN OnHand oh ON oh.store_id = spp.store_id AND oh.product_id = spp.product_id
    JOIN zava.SupplierProduct sp ON sp.product_id = spp.product_id
    WHERE ISNULL(oh.on_hand_qty,0) <= spp.reorder_point
  ),
  -- aggregate per supplier & store for PO header creation
  HeaderGroups AS (
    SELECT supplier_id, store_id
    FROM Cand
    GROUP BY supplier_id, store_id
  )
  -- Create PO headers
  INSERT INTO zava.PurchaseOrder (po_number, supplier_id, store_id, order_date, expected_delivery_date, status)
  OUTPUT INSERTED.po_id, INSERTED.supplier_id, INSERTED.store_id
  SELECT
    CONCAT('PO-', NEXT VALUE FOR zava.seq_po_number),
    hg.supplier_id, hg.store_id,
    @asof_date,
    DATEADD(DAY, MIN(c.lead_time_days), @asof_date),
    'APPROVED'
  FROM HeaderGroups hg
  JOIN Cand c ON c.supplier_id = hg.supplier_id AND c.store_id = hg.store_id
  GROUP BY hg.supplier_id, hg.store_id;

  -- Insert PO Lines for the newly created POs
  ;WITH LatestPO AS (
    SELECT po_id, supplier_id, store_id, expected_delivery_date
    FROM zava.PurchaseOrder
    WHERE order_date = @asof_date
  )
  INSERT INTO zava.PurchaseOrderLine (po_id, product_id, qty_ordered, unit_price_eur)
  SELECT lpo.po_id, c.product_id,
         c.reorder_qty,
         c.price_eur
  FROM LatestPO lpo
  JOIN Cand c ON c.supplier_id = lpo.supplier_id AND c.store_id = lpo.store_id;

  -- Update PO totals
  UPDATE p
  SET total_amount_eur = x.total_amount
  FROM zava.PurchaseOrder p
  JOIN (
    SELECT po_id, SUM(line_amount_eur) AS total_amount
    FROM zava.PurchaseOrderLine
    GROUP BY po_id
  ) x ON x.po_id = p.po_id
  WHERE p.order_date = @asof_date;

  -- Optionally create future RECEIPT inventory transactions on expected date
  IF @create_future_receipts = 1
  BEGIN
    INSERT INTO zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference)
    SELECT p.store_id, pol.product_id, 'RECEIPT',
           pol.qty_ordered,
           CAST(p.expected_delivery_date AS DATETIME2(0)),
           CONCAT('PO-RECEIPT:', p.po_number)
    FROM zava.PurchaseOrder p
    JOIN zava.PurchaseOrderLine pol ON pol.po_id = p.po_id
    WHERE p.order_date = @asof_date;
  END
END
GO


-- Generate tonight’s replenishment run
EXEC zava.sp_AutoReplenish @asof_date = CAST(GETDATE() AS DATE), @create_future_receipts = 1;