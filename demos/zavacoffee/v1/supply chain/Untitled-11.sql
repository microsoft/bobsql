/* ============================================================
   daZava Coffee — Supply Chain Seed Script (Azure SQL safe)
   - Creates stores, suppliers, products
   - SupplierProduct mapping & StoreProductParam
   - Initial inventory
   - 90 days of sales using a tally CTE (no master..spt_values)
   ============================================================ */

------------------------------------------------------------
-- [Optional] Reset for re-seeding (UNCOMMENT to use)
-- Order matters because of FKs.
------------------------------------------------------------
/*
DELETE FROM zava.InventoryTransaction;
DELETE FROM zava.PurchaseOrderLine;
DELETE FROM zava.PurchaseOrder;
DELETE FROM zava.StoreProductParam;
DELETE FROM zava.SupplierProduct;
DELETE FROM zava.Product;
DELETE FROM zava.Supplier;
DELETE FROM zava.Store;
*/

------------------------------------------------------------
-- STORES (25 across Europe)
------------------------------------------------------------
INSERT INTO zava.Store (store_code, store_name, city, country, timezone, open_date, status, footfall_index)
VALUES
('STPAR01','Zava Paris Opéra','Paris','France','Europe/Paris','2021-04-01','OPEN',1.25),
('STPAR02','Zava Paris Marais','Paris','France','Europe/Paris','2022-07-12','OPEN',1.10),
('STLON01','Zava London Soho','London','UK','Europe/London','2020-09-15','OPEN',1.30),
('STLON02','Zava London City','London','UK','Europe/London','2021-10-20','OPEN',1.20),
('STBER01','Zava Berlin Mitte','Berlin','Germany','Europe/Berlin','2020-03-10','OPEN',1.10),
('STBER02','Zava Berlin West','Berlin','Germany','Europe/Berlin','2023-01-20','OPEN',0.95),
('STMAD01','Zava Madrid Centro','Madrid','Spain','Europe/Madrid','2019-11-05','OPEN',1.05),
('STBAR01','Zava Barcelona Born','Barcelona','Spain','Europe/Madrid','2021-05-25','OPEN',1.00),
('STAMS01','Zava Amsterdam Zuid','Amsterdam','Netherlands','Europe/Amsterdam','2019-06-10','OPEN',0.95),
('STBRU01','Zava Brussels Grand-Place','Brussels','Belgium','Europe/Brussels','2020-01-15','OPEN',0.90),
('STROM01','Zava Rome Centro','Rome','Italy','Europe/Rome','2022-03-01','OPEN',1.05),
('STMIL01','Zava Milan Duomo','Milan','Italy','Europe/Rome','2022-11-10','OPEN',1.15),
('STVIE01','Zava Vienna Innere Stadt','Vienna','Austria','Europe/Vienna','2020-02-22','OPEN',0.90),
('STZRH01','Zava Zurich Altstadt','Zurich','Switzerland','Europe/Zurich','2021-01-31','OPEN',0.85),
('STCPH01','Zava Copenhagen Nyhavn','Copenhagen','Denmark','Europe/Copenhagen','2020-10-10','OPEN',0.85),
('STOSL01','Zava Oslo Sentrum','Oslo','Norway','Europe/Oslo','2020-08-01','OPEN',0.80),
('STSTO01','Zava Stockholm City','Stockholm','Sweden','Europe/Stockholm','2019-03-15','OPEN',0.95),
('STDUB01','Zava Dublin Temple Bar','Dublin','Ireland','Europe/Dublin','2021-09-09','OPEN',0.88),
('STLIS01','Zava Lisbon Baixa','Lisbon','Portugal','Europe/Lisbon','2021-12-12','OPEN',0.85),
('STATH01','Zava Athens Plaka','Athens','Greece','Europe/Athens','2023-02-14','OPEN',0.80),
('STPRG01','Zava Prague Old Town','Prague','Czechia','Europe/Prague','2020-05-05','OPEN',0.82),
('STWAW01','Zava Warsaw Śródmieście','Warsaw','Poland','Europe/Warsaw','2020-04-20','OPEN',0.78),
('STBUD01','Zava Budapest City','Budapest','Hungary','Europe/Budapest','2021-03-18','OPEN',0.76),
('STHEL01','Zava Helsinki Keskusta','Helsinki','Finland','Europe/Helsinki','2022-05-05','OPEN',0.75),
('STEDB01','Zava Edinburgh New Town','Edinburgh','UK','Europe/London','2020-12-12','OPEN',0.70);
GO

------------------------------------------------------------
-- SUPPLIERS (6)
------------------------------------------------------------
INSERT INTO zava.Supplier (supplier_code, supplier_name, category, incoterms, contact_email, lead_time_default_days)
VALUES
('SUPCOF1','Nordic Roasters AB','Coffee','DAP','orders@nordicroasters.eu',3),
('SUPCOF2','Mediterraneo Roastery SRL','Coffee','DAP','orders@medroast.it',4),
('SUPDAI1','EuroDairy Cooperative','Dairy','DAP','orders@eurodairy.eu',2),
('SUPBAK1','PanEuropa Bakery','Bakery','DAP','orders@paneuropa.eu',2),
('SUPSYP1','SweetSyrups GmbH','Syrups','DAP','orders@sweetsyrups.de',3),
('SUPPAC1','PackPro EU','Packaging','DAP','orders@packpro.eu',5);
GO

------------------------------------------------------------
-- PRODUCTS (~35 SKUs)
------------------------------------------------------------
INSERT INTO zava.Product (sku, product_name, category, uom, perishable, shelf_life_days)
VALUES
('BEAN-ESP-1KG','Espresso Beans Blend A 1kg','Beans','kg',0,NULL),
('BEAN-ESP-ORG-1KG','Espresso Beans Organic 1kg','Beans','kg',0,NULL),
('BEAN-FILT-1KG','Filter Beans 1kg','Beans','kg',0,NULL),
('MILK-WHOLE-1L','Whole Milk 1L','Dairy','L',1,10),
('MILK-OAT-1L','Oat Milk 1L','Dairy','L',1,180),
('MILK-SKIM-1L','Skim Milk 1L','Dairy','L',1,10),
('PASTR-CROISS-80G','Butter Croissant 80g','Bakery','pcs',1,3),
('PASTR-PAINCH-85G','Pain au Chocolat 85g','Bakery','pcs',1,3),
('PASTR-BANANA-CAKE','Banana Bread Slice','Bakery','pcs',1,5),
('SYRP-VAN-1L','Vanilla Syrup 1L','Syrup','bottle',0,365),
('SYRP-CAR-1L','Caramel Syrup 1L','Syrup','bottle',0,365),
('SYRP-HAZ-1L','Hazelnut Syrup 1L','Syrup','bottle',0,365),
('CUP-HOT-12OZ','Hot Cup 12oz','Packaging','pcs',0,NULL),
('CUP-HOT-16OZ','Hot Cup 16oz','Packaging','pcs',0,NULL),
('LID-HOT-12-16','Hot Lid 12/16oz','Packaging','pcs',0,NULL),
('CUP-COLD-16OZ','Cold Cup 16oz','Packaging','pcs',0,NULL),
('LID-COLD-16OZ','Cold Lid 16oz','Packaging','pcs',0,NULL),
('STRAW-PAPER','Paper Straw','Packaging','pcs',0,NULL),
('NAPKIN-COCKTAIL','Cocktail Napkin','Packaging','pcs',0,NULL),
('BEAN-DECAF-1KG','Decaf Beans 1kg','Beans','kg',0,NULL),
('MILK-ALM-1L','Almond Milk 1L','Dairy','L',1,180),
('PASTR-MUFF-BLUE','Blueberry Muffin','Bakery','pcs',1,5),
('PASTR-MUFF-CHOC','Chocolate Muffin','Bakery','pcs',1,5),
('SYRP-TOFF-1L','Toffee Syrup 1L','Syrup','bottle',0,365),
('SYRP-PEP-1L','Peppermint Syrup 1L','Syrup','bottle',0,365),
('CUP-HOT-8OZ','Hot Cup 8oz','Packaging','pcs',0,NULL),
('LID-HOT-8OZ','Hot Lid 8oz','Packaging','pcs',0,NULL),
('BEAN-SINGLE-1KG','Single Origin Beans 1kg','Beans','kg',0,NULL),
('SYRP-PIST-1L','Pistachio Syrup 1L','Syrup','bottle',0,365),
('PASTR-SCONE-PLN','Plain Scone','Bakery','pcs',1,4),
('PASTR-SCONE-RAIS','Raisin Scone','Bakery','pcs',1,4),
('MILK-LACTFREE-1L','Lactose-Free Milk 1L','Dairy','L',1,60),
('CUP-CARRIER-4','Cup Carrier 4-slot','Packaging','pcs',0,NULL),
('BEAN-HOUSE-1KG','House Beans 1kg','Beans','kg',0,NULL),
('SYRP-CHOC-1L','Chocolate Sauce 1L','Syrup','bottle',0,365);
GO

------------------------------------------------------------
-- SUPPLIER → PRODUCT mapping (pricing, pack, lead time)
------------------------------------------------------------
-- Coffee from two roasters (both supply all Bean SKUs)
INSERT INTO zava.SupplierProduct (supplier_id, product_id, price_eur, pack_size, min_order_qty, lead_time_days)
SELECT s.supplier_id, p.product_id,
       CASE WHEN p.sku LIKE 'BEAN-%' THEN 14.50 ELSE 0 END AS price_eur,
       1.000, 5.000,
       ISNULL(s.lead_time_default_days,3)
FROM zava.Supplier s
JOIN zava.Product  p ON s.category='Coffee' AND p.category='Beans';

-- Dairy from EuroDairy
INSERT INTO zava.SupplierProduct (supplier_id, product_id, price_eur, pack_size, min_order_qty, lead_time_days)
SELECT s.supplier_id, p.product_id,
       CASE p.sku
         WHEN 'MILK-WHOLE-1L'    THEN 0.90
         WHEN 'MILK-SKIM-1L'     THEN 0.85
         WHEN 'MILK-OAT-1L'      THEN 1.40
         WHEN 'MILK-ALM-1L'      THEN 1.50
         WHEN 'MILK-LACTFREE-1L' THEN 1.60
       END,
       1.000, 24.000,
       ISNULL(s.lead_time_default_days,2)
FROM zava.Supplier s
JOIN zava.Product  p ON s.category='Dairy' AND p.category='Dairy';

-- Bakery from PanEuropa
INSERT INTO zava.SupplierProduct (supplier_id, product_id, price_eur, pack_size, min_order_qty, lead_time_days)
SELECT s.supplier_id, p.product_id,
       CASE WHEN p.category='Bakery' THEN 0.80 ELSE 0 END,
       1.000, 48.000,
       ISNULL(s.lead_time_default_days,2)
FROM zava.Supplier s
JOIN zava.Product  p ON s.category='Bakery' AND p.category='Bakery';

-- Syrups from SweetSyrups
INSERT INTO zava.SupplierProduct (supplier_id, product_id, price_eur, pack_size, min_order_qty, lead_time_days)
SELECT s.supplier_id, p.product_id,
       6.50, 1.000, 6.000,
       ISNULL(s.lead_time_default_days,3)
FROM zava.Supplier s
JOIN zava.Product  p ON s.category='Syrups' AND p.category='Syrup';

-- Packaging from PackPro (packs of 50; MOQ 200)
INSERT INTO zava.SupplierProduct (supplier_id, product_id, price_eur, pack_size, min_order_qty, lead_time_days)
SELECT s.supplier_id, p.product_id,
       CASE WHEN p.category='Packaging' THEN 0.05 ELSE 0 END,
       50.000, 200.000,
       ISNULL(s.lead_time_default_days,5)
FROM zava.Supplier s
JOIN zava.Product  p ON s.category='Packaging' AND p.category='Packaging';
GO

------------------------------------------------------------
-- StoreProductParam (reorder policies derived by category & footfall)
------------------------------------------------------------
;WITH StoreX AS (
  SELECT store_id, footfall_index FROM zava.Store
),
ProdX AS (
  SELECT product_id, category FROM zava.Product
)
INSERT INTO zava.StoreProductParam (store_id, product_id, reorder_point, reorder_qty, safety_stock, max_stock)
SELECT s.store_id, p.product_id,
       CAST(CASE p.category
              WHEN 'Beans'     THEN 5.0   -- kg
              WHEN 'Dairy'     THEN 40.0  -- L
              WHEN 'Bakery'    THEN 80.0  -- pcs
              WHEN 'Syrup'     THEN 6.0   -- bottles
              WHEN 'Packaging' THEN 400.0 -- pcs
            END * s.footfall_index AS DECIMAL(12,3)),
       CAST(CASE p.category
              WHEN 'Beans'     THEN 10.0
              WHEN 'Dairy'     THEN 80.0
              WHEN 'Bakery'    THEN 160.0
              WHEN 'Syrup'     THEN 12.0
              WHEN 'Packaging' THEN 800.0
            END * s.footfall_index AS DECIMAL(12,3)),
       CAST(CASE p.category
              WHEN 'Beans'     THEN 2.5
              WHEN 'Dairy'     THEN 15.0
              WHEN 'Bakery'    THEN 30.0
              WHEN 'Syrup'     THEN 3.0
              WHEN 'Packaging' THEN 100.0
            END * s.footfall_index AS DECIMAL(12,3)),
       CAST(CASE p.category
              WHEN 'Beans'     THEN 25.0
              WHEN 'Dairy'     THEN 200.0
              WHEN 'Bakery'    THEN 300.0
              WHEN 'Syrup'     THEN 30.0
              WHEN 'Packaging' THEN 3000.0
            END * s.footfall_index AS DECIMAL(12,3))
FROM StoreX s CROSS JOIN ProdX p;
GO

------------------------------------------------------------
-- Initial inventory (ADJUST to ~reorder_point + safety_stock with noise)
------------------------------------------------------------
INSERT INTO zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference)
SELECT spp.store_id, spp.product_id, 'ADJUST',
       CEILING(spp.reorder_point + spp.safety_stock + (ABS(CHECKSUM(NEWID())) % 20)) * 1.0,
       DATEADD(DAY,-90,CAST(GETDATE() AS DATE)),
       'INIT-STOCK'
FROM zava.StoreProductParam spp;
GO

------------------------------------------------------------
-- Generate 90 days of SALES (Azure SQL DB safe; no master..spt_values)
------------------------------------------------------------
DECLARE @days_back int = 90; -- adjust as desired

;WITH Tally(N) AS (
    -- Produces at least @days_back rows: 0.. via 10×10×10 cross join
    SELECT TOP (@days_back)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS N
    FROM (VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) A(n)
    CROSS JOIN (VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) B(n)
    CROSS JOIN (VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) C(n)
),
Calendar AS (
    -- Last @days_back days, inclusive of today
    SELECT CAST(DATEADD(DAY, -(@days_back - 1) + N, CAST(GETDATE() AS DATE)) AS DATE) AS d
    FROM Tally
),
Base AS (
    SELECT s.store_id, s.footfall_index, p.product_id, p.category
    FROM zava.Store s
    CROSS JOIN zava.Product p
),
Demand AS (
    SELECT b.store_id, b.product_id, c.d,
           -- base mean per category per day
           CASE b.category
             WHEN 'Beans'     THEN 2.5
             WHEN 'Dairy'     THEN 18.0
             WHEN 'Bakery'    THEN 40.0
             WHEN 'Syrup'     THEN 1.2
             WHEN 'Packaging' THEN 60.0
           END * b.footfall_index
           * (1.0 + ((ABS(CHECKSUM(NEWID())) % 21) - 10)/100.0) -- ±10% noise
           AS est_qty
    FROM Base b
    CROSS JOIN Calendar c
)
INSERT INTO zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference)
SELECT d.store_id, d.product_id, 'SALE',
       -1.0 * ROUND(d.est_qty,0),
       DATEADD(HOUR, ABS(CHECKSUM(NEWID())) % 12, CAST(d.d AS DATETIME2(0))), -- spread within day
       'DAILY-SALES'
FROM Demand d
WHERE d.est_qty > 0;
GO

------------------------------------------------------------
-- (Optional) Quick checks
------------------------------------------------------------
SELECT COUNT(*) AS stores FROM zava.Store;
SELECT COUNT(*) AS suppliers FROM zava.Supplier;
SELECT COUNT(*) AS products FROM zava.Product;
SELECT COUNT(*) AS supplier_products FROM zava.SupplierProduct;
SELECT COUNT(*) AS store_product_params FROM zava.StoreProductParam;
SELECT COUNT(*) AS init_adjusts FROM zava.InventoryTransaction WHERE reference='INIT-STOCK';
SELECT COUNT(*) AS sales_rows FROM zava.InventoryTransaction WHERE txn_type='SALE';