/* ============================================================
   H) CHECKS
   ============================================================ */
SELECT COUNT(*) AS stores_in_pos FROM zava.RefStore;
SELECT COUNT(*) AS menu_items   FROM zava.MenuItem;
SELECT COUNT(*) AS orders_added FROM zava.SalesOrder WHERE notes LIKE CONCAT('%', @SeedBatchTag, '%');
SELECT COUNT(*) AS lines_added  FROM zava.SalesOrderLine sol
JOIN zava.SalesOrder so ON so.order_id = sol.order_id
WHERE so.notes LIKE CONCAT('%', @SeedBatchTag, '%');

SELECT TOP 5 so.order_number, so.store_id, so.channel, so.created_utc,
       so.subtotal_eur, so.tax_eur, so.tip_eur, so.total_eur
FROM zava.SalesOrder so
WHERE so.notes LIKE CONCAT('%', @SeedBatchTag, '%')
ORDER BY so.created_utc DESC;
