/* ============================================================
   SHIPMENTS (1:1 with PO) + DELIVERY (1:1 with Shipment)
   DELIVERY LINES from PO Lines (simulate small variance)
   ============================================================ */

-- Shipments
INSERT zava.Shipment (shipment_number, supplier_id, store_id, carrier_id, tracking_number, incoterms, status,
                      created_utc, planned_pickup_utc, planned_delivery_utc, weight_kg, volume_m3, notes)
OUTPUT INSERTED.shipment_id, INSERTED.store_id, INSERTED.supplier_id INTO #tmp_sh (shipment_id, store_id, supplier_id)
SELECT CONCAT('SH-', RIGHT('000000'+CAST(NEXT VALUE FOR zava.seq_shipment_number AS varchar(20)),6)) AS shipment_number,
       po.supplier_id, po.store_id, NULL,
       CONCAT('TRK', RIGHT('000000'+CAST(ABS(CHECKSUM(po.po_id)) % 999999 + 1 AS varchar(6)),6)),
       (SELECT TOP 1 incoterms FROM zava.Supplier s WHERE s.supplier_id = po.supplier_id),
       'DISPATCHED',
       SYSUTCDATETIME(),
       DATEADD(DAY, -1, CAST(po.expected_delivery_date AS datetime2(0))),
       CAST(po.expected_delivery_date AS datetime2(0)),
       CAST( CHOOSE(1 + (ABS(CHECKSUM(po.po_id)) % 5), 50.0, 75.0, 100.0, 150.0, 200.0) AS decimal(12,3)),
       CAST( CHOOSE(1 + (ABS(CHECKSUM(po.po_id)) % 5), 1.0, 1.5, 2.0, 2.5, 3.0) AS decimal(12,3)),
       NULL
FROM zava.PurchaseOrder po;

-- Bridge
INSERT zava.ShipmentPO (shipment_id, po_id)
SELECT sh.shipment_id, po.po_id
FROM #tmp_sh sh
JOIN zava.PurchaseOrder po ON po.store_id = sh.store_id AND po.supplier_id = sh.supplier_id
WHERE NOT EXISTS (SELECT 1 FROM zava.ShipmentPO sp WHERE sp.shipment_id = sh.shipment_id AND sp.po_id = po.po_id);

-- Deliveries (1 per shipment)
IF OBJECT_ID('tempdb..#tmp_dl') IS NOT NULL DROP TABLE #tmp_dl;
CREATE TABLE #tmp_dl (delivery_id bigint, shipment_id bigint);

INSERT zava.Delivery (delivery_number, shipment_id, store_id, status, check_in_utc, check_out_utc, received_by, created_utc, discrepancy_flag, comments)
OUTPUT INSERTED.delivery_id, INSERTED.shipment_id INTO #tmp_dl(delivery_id, shipment_id)
SELECT CONCAT('DL-', RIGHT('000000'+CAST(NEXT VALUE FOR zava.seq_delivery_number AS varchar(20)),6)) AS delivery_number,
       sh.shipment_id, sh.store_id,
       CHOOSE(1 + (ABS(CHECKSUM(sh.shipment_id)) % 3), 'ARRIVED','RECEIVING','COMPLETED') AS status,
       DATEADD(HOUR, -1, SYSUTCDATETIME()),
       SYSUTCDATETIME(),
       N'user:' + CAST(sh.store_id AS nvarchar(10)),
       SYSUTCDATETIME(),
       0, NULL
FROM zava.Shipment sh;

-- Delivery lines from PO lines (allow slight short/over and damage)
INSERT zava.DeliveryLine (delivery_id, po_line_id, product_id, qty_delivered, qty_damaged, lot_code, expiry_date, comments)
SELECT dl.delivery_id, pol.po_line_id, pol.product_id,
       -- delivered around ordered with +/- 0..10%
       CAST( pol.qty_ordered * (0.9 + (ABS(CHECKSUM(pol.po_line_id)) % 21)/100.0) AS decimal(12,3)) AS qty_delivered,
       CAST( CASE WHEN (ABS(CHECKSUM(pol.po_line_id, 7)) % 20)=0 THEN (ABS(CHECKSUM(pol.po_line_id, 11)) % 2) * 1.0 ELSE 0 END AS decimal(12,3)) AS qty_damaged,
       CONCAT('LOT', RIGHT('000000'+CAST(ABS(CHECKSUM(pol.po_line_id)) % 999999 + 1 AS varchar(6)),6)),
       CASE WHEN (SELECT perishable FROM zava.Product WHERE product_id = pol.product_id)=1
            THEN DATEADD(DAY, (SELECT shelf_life_days FROM zava.Product WHERE product_id=pol.product_id)/2, CAST(SYSDATETIME() AS date))
            ELSE NULL END,
       NULL
FROM #tmp_dl dl
JOIN zava.ShipmentPO sp ON sp.shipment_id = dl.shipment_id
JOIN zava.PurchaseOrderLine pol ON pol.po_id = sp.po_id;

-- Occasional exceptions
INSERT zava.DeliveryException (delivery_id, delivery_line_id, code, severity, description)
SELECT TOP (CAST((SELECT COUNT(*)*0.03 FROM zava.DeliveryLine) AS int))   -- ~3%
       dl.delivery_id, dl.delivery_line_id,
       CHOOSE(1 + (ABS(CHECKSUM(dl.delivery_line_id)) % 6), 'SHORT','OVER','DAMAGE','TEMP_BREACH','LATE','OTHER') AS code,
       CHOOSE(1 + (ABS(CHECKSUM(dl.delivery_line_id, 99)) % 3), 'INFO','WARN','CRITICAL') AS severity,
       N'Auto-seeded exception'
FROM zava.DeliveryLine dl
ORDER BY dl.delivery_line_id;

-- Proof of Delivery blobs (12–48 KB each)
INSERT zava.ProofOfDelivery (delivery_id, pod_type, pod_blob)
SELECT d.delivery_id, 'PHOTO',
       CONVERT(varbinary(max), REPLICATE(CAST(0xCC AS varbinary(1)),
              zava._util_RandBetween(ABS(CHECKSUM(d.delivery_id)), @PoDBytesPerDeliveryMin, @PoDBytesPerDeliveryMax)))
FROM zava.Delivery d;
GO