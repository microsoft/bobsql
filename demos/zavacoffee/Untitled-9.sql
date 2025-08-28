-- Add an explicit actual_delivery_date to PurchaseOrder
ALTER TABLE zava.PurchaseOrder
ADD actual_delivery_date DATE NULL;
GO

CREATE OR ALTER PROCEDURE zava.sp_PostDeliveryReceipt
  @shipment_id BIGINT,
  @delivered_utc DATETIME2(0) = NULL,
  @received_by NVARCHAR(100) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @delivered_utc IS NULL SET @delivered_utc = SYSUTCDATETIME();

  IF NOT EXISTS (SELECT 1 FROM zava.Shipment WHERE shipment_id = @shipment_id)
  BEGIN
    RAISERROR('Shipment not found', 16, 1);
    RETURN;
  END

  DECLARE @store_id INT;
  SELECT @store_id = store_id FROM zava.Shipment WHERE shipment_id = @shipment_id;

  -- Delivery header
  DECLARE @delivery_id BIGINT;
  INSERT INTO zava.Delivery (delivery_number, shipment_id, store_id, status, check_in_utc, check_out_utc, received_by)
  VALUES (CONCAT('DL-', NEXT VALUE FOR zava.seq_delivery_number), @shipment_id, @store_id, 'COMPLETED', @delivered_utc, @delivered_utc, @received_by);

  SET @delivery_id = SCOPE_IDENTITY();

  -- Delivery lines (receive ordered qty in full)
  ;WITH POL AS (
    SELECT pol.po_line_id,
           pol.product_id,
           pol.qty_ordered,
           pr.category,
           pr.shelf_life_days
    FROM zava.ShipmentPO sp
    JOIN zava.PurchaseOrderLine pol ON pol.po_id = sp.po_id
    JOIN zava.Product pr ON pr.product_id = pol.product_id
    WHERE sp.shipment_id = @shipment_id
  )
  INSERT INTO zava.DeliveryLine (delivery_id, po_line_id, product_id, qty_delivered, qty_damaged, lot_code, expiry_date)
  SELECT
    @delivery_id,
    pol.po_line_id,
    pol.product_id,
    pol.qty_ordered,
    0,
    NULL,
    CASE WHEN pol.category IN ('Dairy','Bakery') AND pol.shelf_life_days IS NOT NULL
         THEN DATEADD(DAY, pol.shelf_life_days, CAST(@delivered_utc AS DATE))
         ELSE NULL
    END
  FROM POL pol;

  -- Inventory RECEIPT
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

  -- Close POs whose lines are all closed
  UPDATE po
  SET status = 'DELIVERED',
      actual_delivery_date = CAST(@delivered_utc AS DATE)
  FROM zava.PurchaseOrder po
  WHERE po.po_id IN (
    SELECT DISTINCT sp.po_id FROM zava.ShipmentPO sp WHERE sp.shipment_id = @shipment_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM zava.PurchaseOrderLine x WHERE x.po_id = po.po_id AND x.status <> 'CLOSED'
  );

  -- Update shipment
  UPDATE zava.Shipment
  SET status = 'DELIVERED',
      actual_delivery_utc = @delivered_utc
  WHERE shipment_id = @shipment_id;

  -- Delivery header status already 'COMPLETED'
END
GO