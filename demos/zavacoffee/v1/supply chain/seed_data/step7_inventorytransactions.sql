/* RECEIPTS from DeliveryLine (optional) */
INSERT zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference)
SELECT d.store_id, dl.product_id, 'RECEIPT',
       CAST(dl.qty_delivered - dl.qty_damaged AS decimal(12,3)),
       d.check_out_utc,
       CONCAT('DL:', d.delivery_number)
FROM zava.Delivery d
JOIN zava.DeliveryLine dl ON dl.delivery_id = d.delivery_id
WHERE @ReceiptLinesFromDeliveries = 1;
