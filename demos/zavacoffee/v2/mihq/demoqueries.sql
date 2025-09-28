-- Recent activity by store (last 15 minutes)
SELECT s.store_code, COUNT(*) AS txn_count
FROM core.pos_txn t
JOIN core.store s ON s.store_id = t.store_id
WHERE t.txn_ts_utc >= DATEADD(MINUTE, -15, SYSUTCDATETIME())
GROUP BY s.store_code
ORDER BY txn_count DESC;

-- Calculated on-hand (from ledger)
SELECT s.store_code, p.product_sku, SUM(l.qty_delta) AS on_hand_calc
FROM core.inventory_ledger l
JOIN core.store s   ON s.store_id = l.store_id
JOIN core.product p ON p.product_id = l.product_id
GROUP BY s.store_code, p.product_sku
HAVING SUM(l.qty_delta) <> 0
ORDER BY s.store_code, p.product_sku;

-- Hot products in last hour
SELECT TOP (20) p.product_sku, p.product_name, SUM(pl.quantity) AS qty
FROM core.pos_txn_line pl
JOIN core.pos_txn t ON t.pos_txn_id = pl.pos_txn_id
JOIN core.product p ON p.product_id = pl.product_id
WHERE t.txn_ts_utc >= DATEADD(HOUR, -1, SYSUTCDATETIME())
GROUP BY p.product_sku, p.product_name
ORDER BY qty DESC;