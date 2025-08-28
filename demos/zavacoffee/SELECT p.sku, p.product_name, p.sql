SELECT p.sku, p.product_name, p.category,
       SUM(CASE WHEN it.txn_type='SALE' THEN -it.qty ELSE 0 END) AS units_sold
FROM zava.InventoryTransaction it
JOIN zava.Product p ON p.product_id = it.product_id
WHERE it.txn_type='SALE'
GROUP BY p.sku, p.product_name, p.category
ORDER BY units_sold DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

;WITH OnHand AS (
  SELECT store_id, product_id, CAST(txn_dt AS DATE) d, SUM(qty) AS delta
  FROM zava.InventoryTransaction
  GROUP BY store_id, product_id, CAST(txn_dt AS DATE)
),
Cum AS (
  SELECT store_id, product_id, d,
         SUM(delta) OVER (PARTITION BY store_id, product_id ORDER BY d ROWS UNBOUNDED PRECEDING) AS onhand
  FROM OnHand
)
SELECT TOP 20 s.store_code, p.sku, COUNT(*) AS zero_or_negative_days
FROM Cum c
JOIN zava.Store s ON s.store_id = c.store_id
JOIN zava.Product p ON p.product_id = c.product_id
WHERE c.onhand <= 0
GROUP BY s.store_code, p.sku
ORDER BY zero_or_negative_days DESC;

SELECT sup.supplier_name, COUNT(*) AS open_pos, SUM(total_amount_eur) AS value_eur
FROM zava.PurchaseOrder po
JOIN zava.Supplier sup ON sup.supplier_id = po.supplier_id
WHERE po.status IN ('APPROVED','DISPATCHED')
  AND po.expected_delivery_date BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(DAY,7,CAST(GETDATE() AS DATE))
GROUP BY sup.supplier_name
ORDER BY value_eur DESC;
