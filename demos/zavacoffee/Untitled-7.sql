------------------------------------------------------------
-- Confirms delivery for a shipment, receives all PO lines in full.
-- - Creates Delivery header & lines
-- - Inserts InventoryTransaction RECEIPT for delivered - damaged
-- - Closes PO lines and POs when fully received
------------------------------------------------------------
CREATE OR ALTER PROCEDURE zava.sp_PostDeliveryReceipt
  @shipment_id BIGINT,
  @delivered_utc DATETIME2(0) = NULL,
  @received_by NVARCHAR(100) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @delivered_utc IS NULL SET @delivered_utc = SYSUTCDATETIME();

  -- Basic validations
  IF NOT EXISTS (SELECT 1 FROM zava.Shipment WHERE shipment_id = @shipment_id)
  BEGIN
    RAISERROR('Shipment not found', 16, 1);
    RETURN;
  END

  DECLARE @store_id INT;
  SELECT @store_id = store_id FROM zava.Shipment WHERE shipment_id = @shipment_id;

  -- Create Delivery header
  DECLARE @delivery_id BIGINT;
  INSERT INTO zava.Delivery (delivery_number, shipment_id, store_id, status, check_in_utc, check_out_utc, received_by)
  VALUES (CONCAT('DL-', NEXT VALUE FOR zava.seq_delivery_number), @shipment_id, @store_id, 'COMPLETED', @delivered_utc, @delivered_utc, @received_by);

  SET @delivery_id = SCOPE_IDENTITY();

  -- Insert Delivery lines from all PO lines linked to this shipment
  ;WITH POL AS (
    SELECT pol.po_line_id, pol.product_id, pol.qty_ordered, p.category, pr.shelf_life_days
    FROM zava.ShipmentPO sp
    JOIN zava.PurchaseOrderLine pol ON pol.po_id = sp.po_id
    JOIN zava.Product pr ON pr.product_id = pol.product_id
    JOIN zava.Product p   ON p.product_id = pr.product_id
    WHERE sp.shipment_id = @shipment_id
  )
  INSERT INTO zava.DeliveryLine (delivery_id, po_line_id, product_id, qty_delivered, qty_damaged, lot_code, expiry_date)
  SELECT
    @delivery_id,
    pol.po_line_id,
    pol.product_id,
    pol.qty_ordered,  -- assume perfect delivery; adjust in custom flows
    0,
    NULL,
    CASE WHEN (SELECT category FROM zava.Product WHERE product_id = pol.product_id) IN ('Dairy','Bakery')
         THEN DATEADD(DAY, ISNULL((SELECT shelf_life_days FROM zava.Product WHERE product_id = pol.product_id), 5), CAST(@delivered_utc AS DATE))
         ELSE NULL
    END
  FROM zava.ShipmentPO sp
  JOIN zava.PurchaseOrderLine pol ON pol.po_id = sp.po_id
  WHERE sp.shipment_id = @shipment_id;

  -- Inventory RECEIPTs (delivered - damaged)
  INSERT INTO zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference)
  SELECT @store_id, dl.product_id, 'RECEIPT',
         (dl.qty_delivered - dl.qty_damaged),
         @delivered_utc,
         CONCAT('DELIVERY:', (SELECT delivery_number FROM zava.Delivery WHERE delivery_id = @delivery_id))
  FROM zava.DeliveryLine dl
  WHERE dl.delivery_id = @delivery_id
    AND (dl.qty_delivered - dl.qty_damaged) > 0;

  -- Close PO lines fully received
  UPDATE pol
  SET status = 'CLOSED'
  FROM zava.PurchaseOrderLine pol
  WHERE pol.po_line_id IN (SELECT po_line_id FROM zava.DeliveryLine WHERE delivery_id = @delivery_id);

  -- If all lines of a PO are closed, close the PO
  UPDATE po
  SET status = 'DELIVERED',
      actual_delivery_date = CAST(@delivered_utc AS DATE)  -- optional additional column if you add it later
  FROM zava.PurchaseOrder po
  WHERE po.po_id IN (
    SELECT DISTINCT sp.po_id
    FROM zava.ShipmentPO sp
    WHERE sp.shipment_id = @shipment_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM zava.PurchaseOrderLine x
    WHERE x.po_id = po.po_id AND x.status <> 'CLOSED'
  );

  -- Update shipment as delivered
  UPDATE zava.Shipment
  SET status = 'DELIVERED',
      actual_delivery_utc = @delivered_utc
  WHERE shipment_id = @shipment_id;

  -- Mark delivery header as completed
  UPDATE zava.Delivery
  SET status = 'COMPLETED'
  WHERE delivery_id = @delivery_id;
END
