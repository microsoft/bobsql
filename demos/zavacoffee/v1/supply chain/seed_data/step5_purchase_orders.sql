/* ============================================================
   PURCHASE ORDERS & LINES (weekly per store across suppliers)
   ============================================================ */
-- Clean (dev only)
DELETE FROM zava.ShipmentPO;
DELETE FROM zava.DeliveryLine;
DELETE FROM zava.DeliveryException;
DELETE FROM zava.ProofOfDelivery;
DELETE FROM zava.Delivery;
DELETE FROM zava.Shipment;
DELETE FROM zava.PurchaseOrderLine;
DELETE FROM zava.PurchaseOrder;

-- Create a calendar of Mondays in the range
IF OBJECT_ID('tempdb..#Weeks') IS NOT NULL DROP TABLE #Weeks;
CREATE TABLE #Weeks (week_start date primary key);
WITH d AS (
  SELECT @StartDate AS d
  UNION ALL SELECT DATEADD(DAY, 1, d) FROM d WHERE d < @EndDate
)
INSERT #Weeks(week_start)
SELECT DISTINCT DATEADD(DAY, -((DATEPART(WEEKDAY, d) + 5) % 7), d) -- Monday start (US setting)
FROM d OPTION (MAXRECURSION 0);

-- Distribute POs per store per week across suppliers
DECLARE @NowUtc datetime2(0) = SYSUTCDATETIME();

;WITH plan AS (
  SELECT s.store_id, w.week_start,
         (ABS(CHECKSUM(s.store_id, w.week_start)) % (@POsPerStorePerWeek)) + 1 AS pos_this_week
  FROM zava.Store s
  CROSS JOIN #Weeks w
),
po_sched AS (
  SELECT p.store_id, p.week_start, n.n AS seq
  FROM plan p
  CROSS APPLY (SELECT TOP (p.pos_this_week) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
               FROM zava._util_GetNumbers(@POsPerStorePerWeek)) n
),
pick_supplier AS (
  SELECT ps.store_id, ps.week_start, ps.seq,
         ((ABS(CHECKSUM(ps.store_id, ps.week_start, ps.seq)) % @SupplierCount) + 1) AS supplier_rn
  FROM po_sched ps
)
INSERT zava.PurchaseOrder (po_number, supplier_id, store_id, order_date, expected_delivery_date, status, total_amount_eur, created_utc)
OUTPUT INSERTED.po_id, INSERTED.store_id, INSERTED.supplier_id, INSERTED.order_date INTO #tmp_po (po_id, store_id, supplier_id, order_date)
SELECT CONCAT('PO-', RIGHT('000000'+CAST(ABS(CHECKSUM(store_id, week_start, seq)) % 999999 + 1 AS varchar(6)),6)) AS po_number,
       s.supplier_id,
       ps.store_id,
       DATEADD(DAY, (ABS(CHECKSUM(ps.store_id, ps.week_start, ps.seq)) % 5), ps.week_start) AS order_date,
       DATEADD(DAY, COALESCE(s.lead_time_default_days, 5),
               DATEADD(DAY, (ABS(CHECKSUM(ps.store_id, ps.week_start, ps.seq)) % 5), ps.week_start)) AS expected_delivery_date,
       'APPROVED',
       NULL,
       @NowUtc
FROM pick_supplier x
JOIN (SELECT supplier_id, ROW_NUMBER() OVER (ORDER BY supplier_id) AS rn FROM zava.Supplier) s ON s.rn = x.supplier_rn;

-- Build PO lines (8..22 lines/PO) from SupplierProduct
IF OBJECT_ID('tempdb..#PoTargets') IS NOT NULL DROP TABLE #PoTargets;
CREATE TABLE #PoTargets(po_id bigint, supplier_id int, store_id int, line_count int);
INSERT #PoTargets
SELECT t.po_id, t.supplier_id, t.store_id,
       zava._util_RandBetween(ABS(CHECKSUM(t.po_id)), @POLinesPerPO_Min, @POLinesPerPO_Max) AS line_count
FROM #tmp_po t;

;WITH pt AS (
  SELECT po_id, supplier_id, store_id, line_count,
         ROW_NUMBER() OVER (PARTITION BY po_id ORDER BY (SELECT NULL)) AS seq
  FROM #PoTargets
),
exp_lines AS (
  SELECT pt.po_id, pt.supplier_id, pt.store_id, n.n AS line_no
  FROM pt
  CROSS APPLY zava._util_GetNumbers(pt.line_count) n
),
pick_products AS (
  SELECT e.po_id, e.store_id, sp.product_id,
         ROW_NUMBER() OVER (PARTITION BY e.po_id ORDER BY ABS(CHECKSUM(e.po_id, sp.product_id))) AS rn
  FROM exp_lines e
  JOIN zava.SupplierProduct sp ON sp.supplier_id = e.supplier_id
),
take_top AS (
  SELECT po_id, store_id, product_id
  FROM pick_products
  WHERE rn <= (SELECT line_count FROM #PoTargets WHERE po_id = pick_products.po_id)
)
INSERT zava.PurchaseOrderLine (po_id, product_id, qty_ordered, unit_price_eur, status)
SELECT tl.po_id,
       tl.product_id,
       CAST( CHOOSE(1 + (ABS(CHECKSUM(tl.po_id, tl.product_id)) % 5), 5.0, 10.0, 20.0, 30.0, 50.0) AS decimal(12,3)) AS qty_ordered,
       CAST(sp.price_eur AS decimal(12,2)) AS unit_price_eur,
       'OPEN'
FROM take_top tl
JOIN zava.SupplierProduct sp ON sp.supplier_id IN (
     SELECT supplier_id FROM #tmp_po WHERE po_id = tl.po_id) AND sp.product_id = tl.product_id;
GO