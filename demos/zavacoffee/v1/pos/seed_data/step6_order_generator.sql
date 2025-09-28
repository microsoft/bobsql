/* ============================================================
   F) ORDERS + LINES + PAYMENTS
   ============================================================ */

-- Guard: need price list items
IF NOT EXISTS (SELECT 1 FROM zava.PriceListItem)
BEGIN
    RAISERROR('No PriceListItem rows found. Seed menu/pricing first (section D).', 16, 1);
    RETURN;
END

-- 1) Build working sets: stores × dates × order counts
IF OBJECT_ID('tempdb..#Days') IS NOT NULL DROP TABLE #Days;
CREATE TABLE #Days(d date NOT NULL PRIMARY KEY);
;WITH d AS (
  SELECT @StartDate AS d
  UNION ALL SELECT DATEADD(DAY, 1, d) FROM d WHERE d < @EndDate
)
INSERT #Days(d) SELECT d FROM d OPTION (MAXRECURSION 0);

IF OBJECT_ID('tempdb..#Plan') IS NOT NULL DROP TABLE #Plan;
CREATE TABLE #Plan (store_id int, d date, order_seq int);

INSERT #Plan(store_id, d, order_seq)
SELECT rs.store_id, dy.d, n.n
FROM zava.RefStore rs
CROSS JOIN #Days dy
CROSS APPLY zava._util_GetNumbers(@OrdersPerStorePerDay) n;

-- 2) Resolve a device per store/channel
IF OBJECT_ID('tempdb..#DevicePerStore') IS NOT NULL DROP TABLE #DevicePerStore;
CREATE TABLE #DevicePerStore (store_id int, device_id_pos int, device_id_kiosk int);

INSERT #DevicePerStore(store_id, device_id_pos, device_id_kiosk)
SELECT rs.store_id,
       (SELECT TOP 1 d.device_id FROM zava.Device d WHERE d.device_type='POS'   ORDER BY ABS(CHECKSUM(rs.store_id, d.device_id))) AS pos_id,
       (SELECT TOP 1 d.device_id FROM zava.Device d WHERE d.device_type='KIOSK' ORDER BY ABS(CHECKSUM(rs.store_id, d.device_id))) AS kiosk_id
FROM zava.RefStore rs;

-- 3) Create Orders (batch insert)
IF OBJECT_ID('tempdb..#NewOrders') IS NOT NULL DROP TABLE #NewOrders;
CREATE TABLE #NewOrders (order_id bigint PRIMARY KEY, store_id int, d date);

;WITH o AS (
  SELECT p.store_id, p.d,
         CASE WHEN (ABS(CHECKSUM(p.store_id, p.d, p.order_seq)) % 100) < @PctKiosk THEN 'KIOSK' ELSE 'POS' END AS channel,
         (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 7)) % 24)   AS hr,
         (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 11)) % 60)  AS mi,
         (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 13)) % 60)  AS ss,
         (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 17)) % 100) < @PctCustomerAttached AS has_customer
  FROM #Plan p
)
INSERT zava.SalesOrder (store_id, device_id, staff_id, customer_id, channel, fulfillment_type,
                        status, created_utc, submitted_utc, completed_utc, pickup_name, notes)
OUTPUT INSERTED.order_id, INSERTED.store_id, CAST(INSERTED.created_utc AS date) INTO #NewOrders(order_id, store_id, d)
SELECT o.store_id,
       CASE o.channel WHEN 'KIOSK' THEN dps.device_id_kiosk ELSE dps.device_id_pos END,
       (SELECT TOP 1 s.staff_id FROM zava.Staff s ORDER BY ABS(CHECKSUM(o.store_id, s.staff_id))) AS staff_id,
       CASE WHEN o.has_customer = 1
            THEN (SELECT TOP 1 c.customer_id FROM zava.Customer c ORDER BY ABS(CHECKSUM(o.store_id, o.hr, o.mi, c.customer_id)))
            ELSE NULL END,
       o.channel,
       CHOOSE(1 + (ABS(CHECKSUM(o.store_id, o.hr)) % 3), 'DINE_IN','TAKEAWAY','PICKUP'),
       'COMPLETED',
       DATEADD(SECOND, o.ss, DATEADD(MINUTE, o.mi, DATEADD(HOUR, o.hr, CAST(o.d AS datetime2(0))))),
       DATEADD(MINUTE, 1, DATEADD(SECOND, o.ss, DATEADD(MINUTE, o.mi, DATEADD(HOUR, o.hr, CAST(o.d AS datetime2(0)))))),
       DATEADD(MINUTE, 8, DATEADD(SECOND, o.ss, DATEADD(MINUTE, o.mi, DATEADD(HOUR, o.hr, CAST(o.d AS datetime2(0)))))),
       NULL,
       CONCAT('Seed ', @SeedBatchTag)
FROM o
JOIN #DevicePerStore dps ON dps.store_id = o.store_id;

-- 4) Lines per order (1..@MaxLinesPerOrder), price from global price list
DECLARE @pl_any int = (SELECT TOP 1 price_list_id FROM zava.PriceList WHERE channel IN ('ANY','POS','KIOSK') ORDER BY priority, effective_from DESC);

IF OBJECT_ID('tempdb..#OrderLinesPlan') IS NOT NULL DROP TABLE #OrderLinesPlan;
CREATE TABLE #OrderLinesPlan(order_id bigint, line_no int);

INSERT #OrderLinesPlan(order_id, line_no)
SELECT no.order_id, x.n
FROM #NewOrders no
CROSS APPLY (SELECT TOP (1 + (ABS(CHECKSUM(no.order_id)) % @MaxLinesPerOrder)) n
             FROM zava._util_GetNumbers(@MaxLinesPerOrder) ORDER BY NEWID()) x;

-- pick menu items
IF OBJECT_ID('tempdb..#PickMenu') IS NOT NULL DROP TABLE #PickMenu;
CREATE TABLE #PickMenu (order_id bigint, line_no int, menu_item_id int, qty decimal(9,3), unit_price_eur decimal(12,2), tax_category_id int);

INSERT #PickMenu(order_id, line_no, menu_item_id, qty, unit_price_eur, tax_category_id)
SELECT olp.order_id, olp.line_no,
       mi.menu_item_id,
       CAST(CHOOSE(1 + (ABS(CHECKSUM(olp.order_id, olp.line_no)) % 3), 1.0, 2.0, 3.0) AS decimal(9,3)) AS qty,
       pli.base_price_eur,
       mi.tax_category_id
FROM #OrderLinesPlan olp
CROSS APPLY (
    SELECT TOP 1 mi.menu_item_id, mi.tax_category_id
    FROM zava.MenuItem mi
    WHERE mi.active = 1
    ORDER BY ABS(CHECKSUM(olp.order_id, olp.line_no, mi.menu_item_id))
) pick
JOIN zava.MenuItem mi ON mi.menu_item_id = pick.menu_item_id
JOIN zava.PriceListItem pli ON pli.price_list_id = @pl_any AND pli.menu_item_id = mi.menu_item_id;

-- compute tax by store/category (latest effective)
IF OBJECT_ID('tempdb..#LineWithTax') IS NOT NULL DROP TABLE #LineWithTax;
CREATE TABLE #LineWithTax(order_id bigint, line_no int, menu_item_id int, qty decimal(9,3), unit_price_eur decimal(12,2),
                          tax_amount_eur decimal(12,2));

INSERT #LineWithTax(order_id, line_no, menu_item_id, qty, unit_price_eur, tax_amount_eur)
SELECT pm.order_id, pm.line_no, pm.menu_item_id, pm.qty, pm.unit_price_eur,
       CAST((pm.qty * pm.unit_price_eur) *
            ISNULL((
              SELECT TOP 1 tr.rate
              FROM zava.SalesOrder so
              JOIN zava.TaxRate tr ON tr.store_id = so.store_id
              JOIN zava.TaxCategory tc ON tc.tax_category_id = pm.tax_category_id AND tr.tax_category_id = tc.tax_category_id
              WHERE so.order_id = pm.order_id
              ORDER BY tr.effective_from DESC
            ), 0.0) AS decimal(12,2)) AS tax_amount_eur
FROM #PickMenu pm;

-- INSERT SalesOrderLine rows
INSERT zava.SalesOrderLine(order_id, line_no, menu_item_id, qty, unit_price_eur, tax_amount_eur, notes)
SELECT lwt.order_id, lwt.line_no, lwt.menu_item_id, lwt.qty, lwt.unit_price_eur, lwt.tax_amount_eur, NULL
FROM #LineWithTax lwt;

-- 5) Roll up order totals
;WITH sums AS (
  SELECT sol.order_id,
         SUM(sol.qty * sol.unit_price_eur) AS subtotal,
         SUM(sol.tax_amount_eur)           AS tax
  FROM zava.SalesOrderLine sol
  JOIN #NewOrders no ON no.order_id = sol.order_id
  GROUP BY sol.order_id
)
UPDATE so
   SET subtotal_eur = s.subtotal,
       tax_eur      = s.tax,
       total_eur    = s.subtotal + ISNULL(so.tip_eur,0) + s.tax
FROM zava.SalesOrder so
JOIN sums s ON s.order_id = so.order_id;

-- 6) Payments (one per order), include small tips
INSERT zava.Payment(order_id, tender_type_code, status, amount_eur, tip_amount_eur, provider, created_utc, card_brand, card_last4)
SELECT no.order_id,
       CHOOSE(1 + (ABS(CHECKSUM(no.order_id, 1)) % 100),
              -- Weighted tender split: CARD 70%, CASH 25%, GIFTCARD 5%
              'CARD','CARD','CARD','CARD','CARD','CARD','CARD',
              'CASH','CASH','CASH','CASH','CASH',
              'GIFTCARD') AS tender,
       'CAPTURED',
       CAST(so.total_eur AS decimal(14,2)),
       CAST(ROUND((CASE WHEN so.channel='KIOSK' THEN 0.05 + (ABS(CHECKSUM(no.order_id, 9)) % 16)/100.0
                        ELSE (ABS(CHECKSUM(no.order_id, 9)) % 11)/100.0 END) * ISNULL(so.subtotal_eur,0), 2) AS decimal(14,2)) AS tip,
       CASE WHEN (ABS(CHECKSUM(no.order_id, 23)) % 100) < 70 THEN 'Adyen' ELSE 'Stripe' END,
       DATEADD(MINUTE, 9, so.created_utc),
       CHOOSE(1 + (ABS(CHECKSUM(no.order_id, 5)) % 4), 'VISA','MC','AMEX','DISC'),
       RIGHT('0000'+CAST(ABS(CHECKSUM(no.order_id, 6)) % 9999 AS varchar(4)),4)
FROM #NewOrders no
JOIN zava.SalesOrder so ON so.order_id = no.order_id;

-- Recompute total incl. tip
UPDATE so
   SET tip_eur   = p.tip_amount_eur,
       total_eur = so.subtotal_eur + so.tax_eur + p.tip_amount_eur
FROM zava.SalesOrder so
JOIN zava.Payment p ON p.order_id = so.order_id;