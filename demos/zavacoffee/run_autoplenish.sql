-- Run replenishment for today (don’t pre-post receipts if you plan to use Shipments/Deliveries)
EXEC zava.sp_AutoReplenish @asof_date = CAST(GETDATE() AS DATE), @create_future_receipts = 0;

-- Inspect the most recent POs
SELECT TOP 20 po_id, po_number, supplier_id, store_id, order_date, expected_delivery_date, status, total_amount_eur
FROM zava.PurchaseOrder
ORDER BY po_id DESC;

-- Check lines for the latest PO
SELECT TOP 50 *
FROM zava.PurchaseOrderLine
WHERE po_id = (SELECT MAX(po_id) FROM zava.PurchaseOrder)
ORDER BY po_line_id;

-- See how many items were below reorder point that triggered lines
SELECT COUNT(*) AS triggered_skus FROM zava.PurchaseOrderLine
WHERE po_id IN (SELECT po_id FROM zava.PurchaseOrder WHERE order_date = CAST(GETDATE() AS DATE));
