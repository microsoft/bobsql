------------------------------------------------------------
-- Shipments currently in transit (including dispatched)
------------------------------------------------------------
CREATE OR ALTER VIEW zava.v_ShipmentsInTransit AS
SELECT sh.shipment_id, sh.shipment_number, sup.supplier_code, st.store_code,
       sh.status, sh.planned_delivery_utc, sh.tracking_number
FROM zava.Shipment sh
JOIN zava.Supplier sup ON sup.supplier_id = sh.supplier_id
JOIN zava.Store st     ON st.store_id     = sh.store_id
WHERE sh.status IN ('DISPATCHED','IN_TRANSIT','OUT_FOR_DELIVERY');
GO

------------------------------------------------------------
-- Deliveries due today (planned or not yet completed)
------------------------------------------------------------
CREATE OR ALTER VIEW zava.v_DeliveriesDueToday AS
SELECT sh.shipment_id, sh.shipment_number, st.store_code,
       CAST(sh.planned_delivery_utc AS DATE) AS due_date,
       sh.status AS shipment_status
FROM zava.Shipment sh
JOIN zava.Store st ON st.store_id = sh.store_id
WHERE CAST(sh.planned_delivery_utc AS DATE) = CAST(GETDATE() AS DATE)
  AND sh.status <> 'DELIVERED';
