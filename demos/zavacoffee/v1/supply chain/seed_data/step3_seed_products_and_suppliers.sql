/* ============================================================
   SUPPLIERS
   ============================================================ */
DELETE FROM zava.Supplier;

;WITH s AS (
  SELECT TOP (@SupplierCount)
         ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
  FROM zava._util_GetNumbers(1000)
)
INSERT zava.Supplier (supplier_code, supplier_name, category, incoterms, contact_email, lead_time_default_days)
SELECT CONCAT('SUP', RIGHT('000'+CAST(rn AS varchar(3)),3)) AS supplier_code,
       CONCAT(N'Zava Partner ', rn) AS supplier_name,
       -- rotate categories
       CHOOSE(1 + (rn % 5), N'Coffee', N'Dairy', N'Bakery', N'Syrups', N'Packaging') AS category,
       CHOOSE(1 + (rn % 4), N'FOB', N'CIF', N'DDP', N'EXW') AS incoterms,
       CONCAT('supplier', rn, '@zava-partners.example') AS contact_email,
       2 + (rn % 10) AS lead_time_default_days;
GO

/* ============================================================
   PRODUCTS
   ============================================================ */
DELETE FROM zava.Product;

;WITH p AS (
  SELECT TOP (@ProductCount)
         ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
  FROM zava._util_GetNumbers(200000)
)
INSERT zava.Product (sku, product_name, category, uom, perishable, shelf_life_days)
SELECT CONCAT('SKU-', RIGHT('000000'+CAST(rn AS varchar(6)),6)) AS sku,
       CONCAT(N'Product ', rn) AS product_name,
       CHOOSE(1 + (rn % 5), N'Beans', N'Dairy', N'Bakery', N'Syrup', N'Packaging') AS category,
       CHOOSE(1 + (rn % 5), N'kg', N'L', N'pcs', N'bottle', N'bag') AS uom,
       CASE WHEN (rn % 5) IN (2,3) THEN 1 ELSE 0 END AS perishable,
       CASE WHEN (rn % 5) IN (2,3) THEN 7 + (rn % 21) ELSE NULL END AS shelf_life_days;
GO