/* ============================================================
   SUPPLIER ↔ PRODUCT (price lists)
   Each product has 1..3 suppliers
   ============================================================ */
DELETE FROM zava.SupplierProduct;

;WITH sp AS (
  SELECT TOP (@ProductCount * 2)
         ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn,
         ((ABS(CHECKSUM(NEWID())) % @SupplierCount) + 1) AS supplier_rn,
         ((ABS(CHECKSUM(NEWID())) % @ProductCount) + 1)  AS product_rn
  FROM zava._util_GetNumbers(@ProductCount * 3)
)
INSERT zava.SupplierProduct (supplier_id, product_id, price_eur, pack_size, min_order_qty, lead_time_days)
SELECT s.supplier_id,
       p.product_id,
       CAST(0.8 + (ABS(CHECKSUM(p.product_id, s.supplier_id)) % 1200)/10.0 AS decimal(12,2)) AS price_eur,
       CAST( CHOOSE(1 + (p.product_id % 5), 1.0, 0.5, 0.25, 2.0, 5.0) AS decimal(12,3)) AS pack_size,
       CAST( CHOOSE(1 + (p.product_id % 4), 1.0, 2.0, 5.0, 10.0) AS decimal(12,3)) AS min_order_qty,
       COALESCE(s.lead_time_default_days, 5)
FROM sp x
JOIN zava.Supplier s ON s.supplier_id = x.supplier_rn
JOIN zava.Product  p ON p.product_id  = x.product_rn
-- avoid duplicates
WHERE NOT EXISTS (SELECT 1 FROM zava.SupplierProduct sp2 WHERE sp2.supplier_id = s.supplier_id AND sp2.product_id = p.product_id);
GO

/* ============================================================
   STORE PRODUCT PARAMS (replenishment policy)
   Each store stocks ~60% of products
   ============================================================ */
DELETE FROM zava.StoreProductParam;

;WITH allpairs AS (
  SELECT s.store_id, p.product_id,
         ABS(CHECKSUM(s.store_id, p.product_id)) AS h
  FROM zava.Store s
  CROSS JOIN (SELECT TOP (@ProductCount) product_id FROM zava.Product ORDER BY product_id) p
),
picked AS (
  SELECT store_id, product_id
  FROM allpairs
  WHERE (h % 10) < 6  -- ~60% carried
)
INSERT zava.StoreProductParam (store_id, product_id, reorder_point, reorder_qty, safety_stock, max_stock)
SELECT store_id, product_id,
       CAST( CHOOSE(1 + (product_id % 4), 5.0, 10.0, 15.0, 20.0) AS decimal(12,3)) AS reorder_point,
       CAST( CHOOSE(1 + (product_id % 4), 5.0, 10.0, 15.0, 20.0) AS decimal(12,3)) AS reorder_qty,
       CAST( CHOOSE(1 + (product_id % 4), 2.0, 3.0, 4.0, 5.0) AS decimal(12,3)) AS safety_stock,
       CAST( CHOOSE(1 + (product_id % 4), 40.0, 60.0, 80.0, NULL) AS decimal(12,3)) AS max_stock
FROM picked;
