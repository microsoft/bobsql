-- Example: join loyalty activity with MI product sales (names here are illustrative)
-- Assume external tables already created to mirrored MI:
--   ext_hq_dim_product(product_key, product_sku, product_name, category, ...)
--   ext_hq_fact_pos_sales(date_key, store_key, product_key, pos_txn_id, quantity, net_amount, txn_ts_utc)

SELECT TOP (50)
    a.account_id,
    c.email,
    p.product_sku,
    p.product_name,
    SUM(f.quantity) AS qty_bought,
    SUM(f.net_amount) AS spent
FROM loyalty.loyalty_account a
JOIN loyalty.customer c
  ON c.customer_id = a.customer_id
JOIN ext_hq_fact_pos_sales f
  ON f.pos_txn_id IN (
      SELECT reference_id 
      FROM loyalty.points_ledger pl
      WHERE pl.account_id = a.account_id 
        AND pl.source_system = 'POS'
    )
JOIN ext_hq_dim_product p
  ON p.product_key = f.product_key
GROUP BY a.account_id, c.email, p.product_sku, p.product_name
ORDER BY spent DESC;
