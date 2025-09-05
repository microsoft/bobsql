-- 1) Generate replenishment (no future receipts, shipments handle receiving)
EXEC zava.sp_AutoReplenish @asof_date = CAST(GETDATE() AS DATE), @create_future_receipts = 0;

-- 2) Create shipments from today’s approved POs
EXEC zava.sp_CreateShipmentsFromApprovedPOs @asof_date = CAST(GETDATE() AS DATE);

-- 3) See what’s in transit
SELECT TOP 10 * FROM zava.v_ShipmentsInTransit ORDER BY planned_delivery_utc;

-- 4) Confirm deliveries planned for today (bulk)
DECLARE @sid BIGINT;
DECLARE c CURSOR FAST_FORWARD FOR
  SELECT shipment_id
  FROM zava.Shipment
  WHERE CAST(planned_delivery_utc AS DATE) = CAST(GETDATE() AS DATE)
    AND status <> 'DELIVERED';
OPEN c;
FETCH NEXT FROM c INTO @sid;
WHILE @@FETCH_STATUS = 0
BEGIN
  EXEC zava.sp_PostDeliveryReceipt @shipment_id = @sid, @received_by = N'DemoUser';
  FETCH NEXT FROM c INTO @sid;
END
CLOSE c; DEALLOCATE c;

-- 5) Check results
SELECT TOP 10 po_number, status, actual_delivery_date
FROM zava.PurchaseOrder
ORDER BY po_id DESC;

SELECT TOP 10 * FROM zava.v_CurrentInventory ORDER BY store_id, product_id;
