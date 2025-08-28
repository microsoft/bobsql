Love it. Let’s make your Zava benchmark feel like TPC‑E—i.e., a read‑dominant, mixed OLTP workload with realistic business logic, multiple transaction types, integrity constraints, non‑uniform access patterns, and a primary throughput metric analogous to tpsE. (Reminder: TPC‑E is an OLTP benchmark with 12 transaction types operating on 33 tables; the official metric is tpsE, the rate of completed Trade‑Result txns. We’ll mirror the ideas, not the exact spec, so results are not comparable to published TPC‑E numbers.) [TPC-E Homepage], [TPC Benchm...at Austin]
Below is a Fabric notebook you can paste into a new T‑SQL or Python notebook to (1) add TPC‑E‑style stored procedures mapped to your Zava schema, (2) generate skewed test data, and (3) drive a mixed transaction workload with a tunable mix and a primary metric tpsZR (Zava‑Result, our analog of Trade‑Result). In Fabric you can run native T‑SQL notebooks or run Python cells with %%tsql -artifact <YourDbName> -type SQLDatabase. Fabric’s SQL Database is based on Azure SQL DB, so T‑SQL procs and the TDS endpoint all work as you expect. [Author and...oft Fabric], [SQL databa...soft Learn], [Connect to...oft Fabric]

Fair‑Use / Scope Note
This harness is TPC‑E‑inspired. It mirrors the spirit (transaction diversity, integrity, read/write mix, skew, and a primary throughput metric), but it is not the official TPC‑E kit, and results must not be presented as TPC‑E compliant. If you want an open-source, fair‑use harness for experimentation, see DBT‑5 and OLTP‑1, both TPC‑E‑inspired. [1870.dvi - type.sk], [GitHub - l...benchmark]

0) Choose your notebook style in Fabric

T‑SQL notebook only: Set T‑SQL as the cell language and add your Fabric SQL Database as the primary data source. Paste the T‑SQL cells below. [Author and...oft Fabric]
Python + T‑SQL magic: Keep the notebook in Python, and prefix T‑SQL cells with:
%%tsql -artifact <YourDbName> -type SQLDatabase (works with SQL Database in Fabric). [Connect to...tebook ...]

1) TPC‑E → Zava transaction mapping (what we’ll drive)
TPC‑E’s public docs describe 12 txn types (read‑only & read‑write), a brokerage business model, and tpsE measured by Trade‑Result. We map them to Zava’s retail supply chain domain like this (we’ll create the procs below): [TPC-E Homepage], [TPC Benchm...at Austin]

TPC‑E conceptZava analog (stored procedure)TypeDescriptionTrade‑Orderzava.usp_PlacePurchaseOrderWriteCreate a PO with multiple lines from a supplier to a storeTrade‑Result(primary metric)zava.usp_ReceiveDeliveryWriteRecord shipment+delivery lines, post RECEIPT inventory txns, close/partial close linesTrade‑Updatezava.usp_UpdatePOOrDeliveryWriteModify PO quantities/dates or capture adjustmentsData‑Maintenancezava.usp_DataMaintenanceWriteUpdate prices, lead times, product status (periodic upkeep)Broker‑Volumezava.usp_SupplierVolumeReadSupplier volume/value over a time windowCustomer‑Positionzava.usp_StoreInventoryPositionReadOn‑hand + on‑order − backorder per store/productMarket‑Watchzava.usp_LowStockWatchReadWatchlist: items at/below reorder or safety stockSecurity‑Detailzava.usp_ProductDetailReadProduct, suppliers, price, lead time, perishabilityTrade‑Lookupzava.usp_PurchaseOrderLookupReadFlexible PO lookups (by store, supplier, date, status)Trade‑Statuszava.usp_OrderDeliveryStatusReadStatus summary for an order/deliveryMarket‑Feedzava.usp_PriceLeadtimeFeedWrite“Ticker” style micro‑updates to price/lead‑timeTrade‑Cleanupzava.usp_CleanupHistoryWriteFinalize statuses, archive/compact transient rows

Why this shape? TPC‑E purposely mixes diverse transaction frames, validates integrity, and emphasizes realistic OLTP patterns vs. synthetic updates. We’ll follow those ideas (constraints, longer transactions, non‑uniform access) and make the primary metric the rate of completed ReceiveDelivery operations (tpsZR) to emulate tpsE. [Overview o...Benchmarks], [TPC-E Homepage]

2) Benchmark catalog objects (T‑SQL)

Creates metadata for runs, per‑transaction counters, and a skew helper.

-- Benchmark metadata (if not already created from prior notebook)
IF OBJECT_ID('zava.BenchmarkRun','U') IS NULL
CREATE TABLE zava.BenchmarkRun
(
    run_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    started_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    completed_utc DATETIME2(3) NULL,
    mix_json      NVARCHAR(2000) NULL,
    notes         NVARCHAR(400) NULL
);

IF OBJECT_ID('zava.BenchmarkTxn','U') IS NULL
CREATE TABLE zava.BenchmarkTxn
(
    run_id        BIGINT NOT NULL,
    txn_name      NVARCHAR(40) NOT NULL,
    worker_id     INT NOT NULL,
    ops           BIGINT NOT NULL,
    avg_ms        FLOAT NOT NULL,
    p95_ms        FLOAT NULL,
    p99_ms        FLOAT NULL,
    started_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    completed_utc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_BenchmarkTxn PRIMARY KEY (run_id, txn_name, worker_id),
    CONSTRAINT FK_BenchmarkTxn_Run FOREIGN KEY (run_id) REFERENCES zava.BenchmarkRun(run_id)
);

-- Skew helper set (Zipf-ish approximation using a bias exponent)
IF OBJECT_ID('zava.fn_pick_skewed_id','FN') IS NOT NULL DROP FUNCTION zava.fn_pick_skewed_id;
GO
CREATE FUNCTION zava.fn_pick_skewed_id
(
    @min_id INT, @max_id INT, @bias FLOAT -- bias 0=uniform; 1.0..1.5 increasingly skewed
)
RETURNS INT
AS
BEGIN
    DECLARE @range INT = @max_id - @min_id + 1;
    DECLARE @r FLOAT = (ABS(CHECKSUM(NEWID())) % 100000) / 100000.0; -- [0,1)
    DECLARE @p FLOAT = POWER(@r, 1.0 / NULLIF(@bias+1e-9,0));  -- increase hotness for larger bias
    RETURN @min_id + CAST(FLOOR(@p * @range) AS INT);
END;
GO

3) Core stored procedures (T‑SQL)

These are the heart of the workload. They enforce RI and simulate business logic like TPC‑E’s multi‑frame transactions, but in Zava’s domain. (Official TPC‑E uses multiple frames per transaction; here we keep each proc transactional for simplicity while preserving read/write complexity.) [TPC-E Homepage]

3.1 Place Purchase Order (Trade‑Order analog)

IF OBJECT_ID('zava.usp_PlacePurchaseOrder','P') IS NOT NULL DROP PROCEDURE zava.usp_PlacePurchaseOrder;
GO
CREATE PROCEDURE zava.usp_PlacePurchaseOrder
    @store_id INT,
    @supplier_id INT,
    @lines INT = 5,            -- 3–8 typical
    @seed INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    DECLARE @order_date DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @po_number NVARCHAR(30) = CONCAT('PO-',FORMAT(ABS(CHECKSUM(NEWID())),'000000000'));

    INSERT INTO zava.PurchaseOrder(po_number, supplier_id, store_id, order_date, expected_delivery_date, status)
    VALUES(@po_number, @supplier_id, @store_id, @order_date, DATEADD(DAY, 3 + ABS(CHECKSUM(NEWID()))%7, @order_date), 'APPROVED');

    DECLARE @po_id BIGINT = SCOPE_IDENTITY();

    ;WITH Pick AS
    (
        SELECT TOP (@lines)
            sp.product_id,
            sp.price_eur,
            CAST(5 + (ABS(CHECKSUM(NEWID()))%45) AS DECIMAL(12,3)) AS qty
        FROM zava.SupplierProduct sp
        WHERE sp.supplier_id = @supplier_id
        ORDER BY NEWID()
    )
    INSERT INTO zava.PurchaseOrderLine(po_id, product_id, qty_ordered, unit_price_eur)
    SELECT @po_id, product_id, qty, price_eur FROM Pick;

    COMMIT;
END;
GO

3.2 Receive Delivery (Trade‑Result analog; primary metric)

IF OBJECT_ID('zava.usp_ReceiveDelivery','P') IS NOT NULL DROP PROCEDURE zava.usp_ReceiveDelivery;
GO
CREATE PROCEDURE zava.usp_ReceiveDelivery
    @po_id BIGINT,
    @damage_rate FLOAT = 0.02
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    DECLARE @po zava.PurchaseOrder;
    -- lock header
    UPDATE zava.PurchaseOrder SET status = status WHERE po_id=@po_id;

    DECLARE @store_id INT, @supplier_id INT, @dlno NVARCHAR(30), @shipment_no NVARCHAR(30);
    SELECT @store_id=po.store_id, @supplier_id=po.supplier_id FROM zava.PurchaseOrder po WHERE po_id=@po_id;

    SET @shipment_no = CONCAT('SH-', FORMAT(NEXT VALUE FOR zava.seq_shipment_number,'000000'));
    INSERT INTO zava.Shipment (shipment_number, supplier_id, store_id, status, planned_delivery_utc)
    VALUES(@shipment_no, @supplier_id, @store_id, 'DELIVERED', SYSUTCDATETIME());
    DECLARE @shipment_id BIGINT = SCOPE_IDENTITY();

    INSERT INTO zava.ShipmentPO(shipment_id, po_id) VALUES(@shipment_id, @po_id);

    SET @dlno = CONCAT('DL-', FORMAT(NEXT VALUE FOR zava.seq_delivery_number,'000000'));
    INSERT INTO zava.Delivery (delivery_number, shipment_id, store_id, status, check_in_utc, check_out_utc)
    VALUES(@dlno, @shipment_id, @store_id, 'COMPLETED', SYSUTCDATETIME(), SYSUTCDATETIME());
    DECLARE @delivery_id BIGINT = SCOPE_IDENTITY();

    -- create delivery lines and inventory RECEIPTs
    INSERT INTO zava.DeliveryLine (delivery_id, po_line_id, product_id, qty_delivered, qty_damaged)
    SELECT @delivery_id, pol.po_line_id, pol.product_id,
           pol.qty_ordered * (0.95 + (ABS(CHECKSUM(NEWID()))%11)/100.0),
           pol.qty_ordered * @damage_rate * (CASE WHEN ABS(CHECKSUM(NEWID()))%100<20 THEN 1 ELSE 0 END)
    FROM zava.PurchaseOrderLine pol
    WHERE pol.po_id = @po_id;

    -- Post inventory
    INSERT INTO zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference)
    SELECT @store_id, dl.product_id, 'RECEIPT', (dl.qty_delivered - dl.qty_damaged), SYSUTCDATETIME(), @dlno
    FROM zava.DeliveryLine dl
    WHERE dl.delivery_id = @delivery_id;

    -- Close PO lines if fully received
    UPDATE pol
      SET status = CASE WHEN dl.qty_delivered >= pol.qty_ordered * 0.99 THEN 'CLOSED' ELSE 'PARTIAL' END
    FROM zava.PurchaseOrderLine pol
    JOIN zava.DeliveryLine dl ON dl.po_line_id = pol.po_line_id
    WHERE pol.po_id = @po_id;

    -- If all closed -> close PO
    IF NOT EXISTS (SELECT 1 FROM zava.PurchaseOrderLine WHERE po_id=@po_id AND status <> 'CLOSED')
        UPDATE zava.PurchaseOrder SET status='DELIVERED', dispatched_utc=SYSUTCDATETIME() WHERE po_id=@po_id;
    ELSE
        UPDATE zava.PurchaseOrder SET status='DISPATCHED', dispatched_utc=SYSUTCDATETIME() WHERE po_id=@po_id;

    COMMIT;
END;
GO

3.3 Update Order/Delivery (Trade‑Update analog)

IF OBJECT_ID('zava.usp_UpdatePOOrDelivery','P') IS NOT NULL DROP PROCEDURE zava.usp_UpdatePOOrDelivery;
GO
CREATE PROCEDURE zava.usp_UpdatePOOrDelivery
    @po_id BIGINT,
    @bump_days INT = 1
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    UPDATE zava.PurchaseOrder
      SET expected_delivery_date = DATEADD(DAY, @bump_days, expected_delivery_date)
    WHERE po_id=@po_id AND status IN ('APPROVED','DISPATCHED');
    COMMIT;
END;
GO

3.4 Data maintenance (prices/lead time)

IF OBJECT_ID('zava.usp_DataMaintenance','P') IS NOT NULL DROP PROCEDURE zava.usp_DataMaintenance;
GO
CREATE PROCEDURE zava.usp_DataMaintenance
    @supplier_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    UPDATE sp
      SET price_eur = ROUND(price_eur * (0.98 + (ABS(CHECKSUM(NEWID()))%5)/100.0), 2),
          lead_time_days = LEAST(30, GREATEST(1, lead_time_days + (ABS(CHECKSUM(NEWID()))%3) - 1))
    FROM zava.SupplierProduct sp
    WHERE @supplier_id IS NULL OR sp.supplier_id=@supplier_id;
    COMMIT;
END;
GO

3.5 Read‑only procs (Broker‑Volume / Customer‑Position / etc.)

IF OBJECT_ID('zava.usp_SupplierVolume','P') IS NOT NULL DROP PROCEDURE zava.usp_SupplierVolume;
GO
CREATE PROCEDURE zava.usp_SupplierVolume
    @days INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (20) s.supplier_name,
           COUNT(DISTINCT po.po_id) AS pos,
           SUM(pol.line_amount_eur) AS value_eur
    FROM zava.PurchaseOrder po
    JOIN zava.PurchaseOrderLine pol ON pol.po_id=po.po_id
    JOIN zava.Supplier s ON s.supplier_id=po.supplier_id
    WHERE po.order_date >= DATEADD(DAY, -@days, CAST(SYSUTCDATETIME() AS DATE))
    GROUP BY s.supplier_name
    ORDER BY value_eur DESC;
END;
GO

IF OBJECT_ID('zava.usp_StoreInventoryPosition','P') IS NOT NULL DROP PROCEDURE zava.usp_StoreInventoryPosition;
GO
CREATE PROCEDURE zava.usp_StoreInventoryPosition
    @store_id INT
AS
BEGIN
    SET NOCOUNT ON;
    WITH inv AS (
        SELECT product_id, SUM(qty) AS on_hand
        FROM zava.InventoryTransaction WHERE store_id=@store_id GROUP BY product_id
    ),
    onorder AS (
        SELECT pol.product_id, SUM(pol.qty_ordered) AS on_order
        FROM zava.PurchaseOrder po
        JOIN zava.PurchaseOrderLine pol ON pol.po_id=po.po_id
        WHERE po.store_id=@store_id AND po.status IN ('APPROVED','DISPATCHED')
        GROUP BY pol.product_id
    )
    SELECT p.sku, COALESCE(inv.on_hand,0) AS on_hand, COALESCE(onorder.on_order,0) AS on_order
    FROM zava.Product p
    LEFT JOIN inv ON inv.product_id=p.product_id
    LEFT JOIN onorder ON onorder.product_id=p.product_id
    ORDER BY (COALESCE(inv.on_hand,0)+COALESCE(onorder.on_order,0));
END;
GO

IF OBJECT_ID('zava.usp_LowStockWatch','P') IS NOT NULL DROP PROCEDURE zava.usp_LowStockWatch;
GO
CREATE PROCEDURE zava.usp_LowStockWatch
    @store_id INT
AS
BEGIN
    SET NOCOUNT ON;
    WITH inv AS (
        SELECT product_id, SUM(qty) AS on_hand
        FROM zava.InventoryTransaction WHERE store_id=@store_id GROUP BY product_id
    )
    SELECT p.sku, spp.reorder_point, spp.safety_stock, COALESCE(inv.on_hand,0) AS on_hand
    FROM zava.StoreProductParam spp
    JOIN zava.Product p ON p.product_id=spp.product_id
    LEFT JOIN inv ON inv.product_id=spp.product_id
    WHERE spp.store_id=@store_id
      AND COALESCE(inv.on_hand,0) <= spp.reorder_point
    ORDER BY on_hand ASC;
END;
GO

4) Workload driver (Python, concurrent; TPC‑E‑style mix)

# --- Parameters you can tune ---
USE_PYODBC = True  # set False to skip the driver
SERVER   = "<your-sql-db-server>.database.windows.net"  # Fabric SQL DB TDS endpoint
DATABASE = "<your-db-name>"                             # same as you used above
AUTH     = "ActiveDirectoryInteractive"                 # or ActiveDirectoryServicePrincipal
UID      = "<app-client-id>"                            # for SPN
PWD      = "<app-client-secret>"                        # for SPN

WORKERS = 12
DURATION_SEC = 180
SKEW_BIAS = 1.2   # 0=uniform; 1.0..1.5 more skew like TPC-E non-uniform access
# TPC-E-like mix: read-dominant with multiple read-only types + write types.
TXN_MIX = {
    "PlacePurchaseOrder":  0.08,   # write   (Trade-Order analog)
    "ReceiveDelivery":     0.12,   # write   (Trade-Result analog) -> primary metric
    "UpdatePOOrDelivery":  0.05,   # write   (Trade-Update)
    "DataMaintenance":     0.03,   # write   (Data-Maintenance)
    "SupplierVolume":      0.15,   # read    (Broker-Volume)
    "StoreInventoryPosition": 0.20,# read    (Customer-Position)
    "LowStockWatch":       0.17,   # read    (Market-Watch)
    "PurchaseOrderLookup": 0.10,   # read    (Trade-Lookup) -> we can route to SELECTs
    "OrderDeliveryStatus": 0.10    # read    (Trade-Status)
}
assert abs(sum(TXN_MIX.values()) - 1.0) < 1e-6

if USE_PYODBC:
    import os, time, math, statistics, random
    import threading
    import pyodbc
    import pandas as pd
    from concurrent.futures import ThreadPoolExecutor, as_completed

    base = f"Driver={{ODBC Driver 18 for SQL Server}};Server={SERVER};Database={DATABASE};Encrypt=Yes;TrustServerCertificate=No;Timeout=60;"
    if AUTH == "ActiveDirectoryServicePrincipal":
        CONN_STR = base + f"Authentication=ActiveDirectoryServicePrincipal;UID={UID};PWD={PWD};"
    else:
        CONN_STR = base + "Authentication=ActiveDirectoryInteractive;"

    # fetch id ranges for skewed selection
    def get_minmax(cur, table, idcol):
        cur.execute(f"SELECT MIN({idcol}), MAX({idcol}) FROM {table}")
        lo, hi = cur.fetchone()
        return int(lo), int(hi)

    # start run
    con = pyodbc.connect(CONN_STR, autocommit=True)
    cur = con.cursor()
    mix_json = str(TXN_MIX)
    cur.execute("INSERT INTO zava.BenchmarkRun(mix_json, notes) VALUES (?, ?)", mix_json, "TPC-E-style mix")
    cur.execute("SELECT SCOPE_IDENTITY()")
    RUN_ID = int(cur.fetchone()[0])
    con.close()

    def pick_skewed(lo, hi, bias):
        r = random.random()
        p = r ** (1.0 / (bias + 1e-9))
        return lo + int(p * (hi - lo + 1))

    # prepare lookup sets
    con0 = pyodbc.connect(CONN_STR, autocommit=True); c0 = con0.cursor()
    s_lo, s_hi = get_minmax(c0, "zava.Store", "store_id")
    sup_lo, sup_hi = get_minmax(c0, "zava.Supplier", "supplier_id")
    po_lo, po_hi = get_minmax(c0, "zava.PurchaseOrder", "po_id")
    con0.close()

    def worker(worker_id:int):
        conn = pyodbc.connect(CONN_STR, autocommit=True)
        cur  = conn.cursor()
        # precompiled call strings
        calls = {
            "PlacePurchaseOrder":     "EXEC zava.usp_PlacePurchaseOrder ?, ?, ?",
            "ReceiveDelivery":        "EXEC zava.usp_ReceiveDelivery ?",
            "UpdatePOOrDelivery":     "EXEC zava.usp_UpdatePOOrDelivery ?, ?",
            "DataMaintenance":        "EXEC zava.usp_DataMaintenance ?",
            "SupplierVolume":         "EXEC zava.usp_SupplierVolume ?",
            "StoreInventoryPosition": "EXEC zava.usp_StoreInventoryPosition ?",
            "LowStockWatch":          "EXEC zava.usp_LowStockWatch ?"
        }
        # simple SELECTs for lookup/status (kept read-only)
        selects = {
            "PurchaseOrderLookup": "SELECT TOP (50) po.po_id, po.status, po.order_date FROM zava.PurchaseOrder po ORDER BY po.po_id DESC",
            "OrderDeliveryStatus": "SELECT TOP (50) d.delivery_id, d.status, d.check_in_utc FROM zava.Delivery d ORDER BY d.delivery_id DESC"
        }

        # build a weighted choice list
        choices=[]; 
        for k,w in TXN_MIX.items(): choices += [k]*max(1,int(w*100))
        end = time.time() + DURATION_SEC
        lat = {k:[] for k in TXN_MIX}
        ops = {k:0 for k in TXN_MIX}
        zr_count = 0

        while time.time() < end:
            txn = random.choice(choices)
            t0 = time.perf_counter_ns()
            try:
                if txn == "PlacePurchaseOrder":
                    store_id = pick_skewed(s_lo, s_hi, SKEW_BIAS)
                    supplier_id = pick_skewed(sup_lo, sup_hi, SKEW_BIAS)
                    cur.execute(calls[txn], store_id, supplier_id, random.randint(3,8))
                elif txn == "ReceiveDelivery":
                    # try to pick a recent PO (more likely to be open)
                    poid = pick_skewed(po_lo, po_hi, SKEW_BIAS)
                    cur.execute(calls[txn], poid)
                    zr_count += 1
                elif txn == "UpdatePOOrDelivery":
                    poid = pick_skewed(po_lo, po_hi, SKEW_BIAS)
                    cur.execute(calls[txn], poid, 1)
                elif txn == "DataMaintenance":
                    sid = None if random.random()<0.5 else pick_skewed(sup_lo, sup_hi, SKEW_BIAS)
                    cur.execute(calls[txn], sid)
                elif txn in ("SupplierVolume",):
                    cur.execute(calls[txn], 30)
                    cur.fetchall()
                elif txn in ("StoreInventoryPosition","LowStockWatch"):
                    cur.execute(calls[txn], pick_skewed(s_lo, s_hi, SKEW_BIAS))
                    cur.fetchall()
                elif txn in selects:
                    cur.execute(selects[txn]); cur.fetchall()
                else:
                    pass
            except Exception as ex:
                # ignore expected occasional contention errors to keep load on
                pass
            t1 = time.perf_counter_ns()
            lat[txn].append((t1 - t0)/1e6)
            ops[txn]+=1

        # summarize and persist results for this worker
        rows=[]
        for k in TXN_MIX:
            if ops[k]>0:
                p95 = statistics.quantiles(lat[k], n=20)[18] if len(lat[k])>=20 else None
                p99 = statistics.quantiles(lat[k], n=100)[98] if len(lat[k])>=100 else None
                rows.append((RUN_ID, k, worker_id, ops[k], statistics.fmean(lat[k]), p95, p99))

        cur.fast_executemany=True
        cur.executemany("INSERT INTO zava.BenchmarkTxn(run_id, txn_name, worker_id, ops, avg_ms, p95_ms, p99_ms) VALUES (?,?,?,?,?,?,?)", rows)
        conn.close()
        return zr_count

    zr_total=0
    start=time.time()
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futures=[ex.submit(worker,i+1) for i in range(WORKERS)]
        for f in as_completed(futures):
            zr_total += f.result()
    elapsed=time.time()-start
    tpsZR = zr_total / elapsed if elapsed>0 else 0.0

    # close the run
    con = pyodbc.connect(CONN_STR, autocommit=True)
    cur = con.cursor()
    cur.execute("UPDATE zava.BenchmarkRun SET completed_utc=SYSUTCDATETIME() WHERE run_id=?", RUN_ID)
    con.close()

    print(f"Run {RUN_ID} complete. tpsZR (ReceiveDelivery/sec) = {tpsZR:.2f}")

5) Quick summaries (T‑SQL)

-- Latest run summary
SELECT TOP (1) br.run_id, br.started_utc, br.completed_utc, br.mix_json, br.notes
FROM zava.BenchmarkRun br
ORDER BY br.run_id DESC;

-- Per-transaction stats
DECLARE @rid BIGINT = (SELECT MAX(run_id) FROM zava.BenchmarkRun);
SELECT txn_name,
       SUM(ops) AS ops,
       AVG(avg_ms) AS avg_ms,
       AVG(p95_ms) AS p95_ms,
       AVG(p99_ms) AS p99_ms
FROM zava.BenchmarkTxn
WHERE run_id=@rid
GROUP BY txn_name
ORDER BY txn_name;



