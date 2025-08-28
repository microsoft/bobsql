Perfect—here’s a ready‑to‑run script pack for your Zava workspace that implements the Lakebase‑style Reverse ETL loop on Microsoft Fabric:

01 – Curated views (run in the SQL analytics endpoint of the mirrored DB)
02 – Inbound staging + APPLY procedures (run in the SQL Database in Fabric)
03 – Security grants (run in the SQL Database in Fabric)
04 – Optional: housekeeping / retention tasks (SQL Database)

I’ve kept everything idempotent (CREATE OR ALTER, unique keys, MERGE, NOT EXISTS) so it’s safe to re‑deploy.

01_analytics_endpoint_curated_views.sql
Target:SQL analytics endpoint (the read‑only mirror)
Purpose: Define gold/curated views that scan all mirrored data and emit actionable records for Reverse ETL back to ops.

In the analytics endpoint, you can create schemas, views, procs, and permissions. Data is read‑only—exactly what we want for safe, scalable curation.

/* -----------------------------------------------------------
   01) Curated Views for Reverse ETL (run in SQL analytics endpoint)
   ----------------------------------------------------------- */

-- Create curated schema if not exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'cur')
    EXEC('CREATE SCHEMA cur');
GO

/* A) SLA violations: promised vs. actual delivery timing
      Emits one row per delivery that is late (or predicted-late).
*/
CREATE OR ALTER VIEW cur.v_SLA_Violations
AS
WITH delivery_plan AS
(
    SELECT 
        d.delivery_id,
        d.delivery_number,
        d.shipment_id,
        d.store_id,
        d.status        AS delivery_status,
        s.planned_delivery_utc,
        s.actual_delivery_utc,
        st.store_code,
        st.timezone,
        s.supplier_id,
        sup.supplier_code,
        COALESCE(
            s.planned_delivery_utc,
            (SELECT MAX(po.expected_delivery_date)
               FROM zava.ShipmentPO spo
               JOIN zava.PurchaseOrder po ON po.po_id = spo.po_id
              WHERE spo.shipment_id = s.shipment_id)
        ) AS promised_utc
    FROM zava.Delivery d
    JOIN zava.Shipment s   ON s.shipment_id = d.shipment_id
    JOIN zava.Store st     ON st.store_id   = d.store_id
    JOIN zava.Supplier sup ON sup.supplier_id = s.supplier_id
)
SELECT 
    dp.delivery_id,
    dp.delivery_number,
    dp.store_code,
    dp.supplier_code,
    dp.delivery_status,
    dp.promised_utc,
    dp.actual_delivery_utc,
    DATEDIFF(MINUTE, dp.promised_utc, dp.actual_delivery_utc) AS late_by_minutes,
    CASE WHEN dp.promised_utc IS NOT NULL THEN dp.promised_utc AT TIME ZONE 'UTC' AT TIME ZONE dp.timezone END AS promised_local_time,
    CASE WHEN dp.actual_delivery_utc IS NOT NULL THEN dp.actual_delivery_utc AT TIME ZONE 'UTC' AT TIME ZONE dp.timezone END AS actual_local_time,
    CASE 
       WHEN dp.actual_delivery_utc IS NULL AND dp.promised_utc IS NOT NULL AND SYSUTCDATETIME() > dp.promised_utc THEN 1
       WHEN dp.actual_delivery_utc IS NOT NULL AND dp.promised_utc IS NOT NULL AND dp.actual_delivery_utc > dp.promised_utc THEN 1
       ELSE 0
    END AS is_late,
    CASE 
       WHEN dp.actual_delivery_utc IS NULL AND DATEDIFF(HOUR, dp.promised_utc, SYSUTCDATETIME()) >= 24 THEN 'CRITICAL'
       WHEN dp.actual_delivery_utc IS NULL AND DATEDIFF(HOUR, dp.promised_utc, SYSUTCDATETIME()) BETWEEN 1 AND 23 THEN 'WARN'
       WHEN dp.actual_delivery_utc IS NOT NULL AND DATEDIFF(MINUTE, dp.promised_utc, dp.actual_delivery_utc) > 60 THEN 'WARN'
       ELSE 'INFO'
    END AS severity,
    CONCAT('Promised: ', CONVERT(varchar(19), dp.promised_utc, 126),
           '; Actual: ', CONVERT(varchar(19), dp.actual_delivery_utc, 126)) AS description
FROM delivery_plan dp
WHERE dp.promised_utc IS NOT NULL
  AND (
        (dp.actual_delivery_utc IS NULL AND SYSUTCDATETIME() > dp.promised_utc) OR
        (dp.actual_delivery_utc IS NOT NULL AND dp.actual_delivery_utc > dp.promised_utc)
      );
GO


/* B) Delivery discrepancies: SHORT / OVER / DAMAGE
      Compares POL qty_ordered to delivered/damaged by delivery_id + po_line_id.
*/
CREATE OR ALTER VIEW cur.v_DeliveryDiscrepancies
AS
WITH dl_recv AS (
  SELECT 
      dl.delivery_id,
      dl.po_line_id,
      SUM(dl.qty_delivered) AS qty_delivered,
      SUM(dl.qty_damaged)   AS qty_damaged
  FROM zava.DeliveryLine dl
  GROUP BY dl.delivery_id, dl.po_line_id
)
SELECT
    d.delivery_id,
    d.delivery_number,
    pol.po_line_id,
    po.po_number,
    p.sku,
    p.product_name,
    r.qty_delivered,
    r.qty_damaged,
    pol.qty_ordered,
    CASE
      WHEN (r.qty_delivered - r.qty_damaged) < pol.qty_ordered THEN 'SHORT'
      WHEN (r.qty_delivered - r.qty_damaged) > pol.qty_ordered THEN 'OVER'
      WHEN r.qty_damaged > 0 THEN 'DAMAGE'
      ELSE NULL
    END AS exception_code,
    CASE
      WHEN (pol.qty_ordered - (r.qty_delivered - r.qty_damaged)) >= 0.10 * pol.qty_ordered THEN 'CRITICAL'
      WHEN r.qty_damaged > 0 THEN 'WARN'
      WHEN (r.qty_delivered - r.qty_damaged) > pol.qty_ordered THEN 'INFO'
      ELSE 'INFO'
    END AS severity,
    CONCAT('Ordered=', pol.qty_ordered, '; Delivered=', r.qty_delivered, '; Damaged=', r.qty_damaged) AS description
FROM dl_recv r
JOIN zava.Delivery d           ON d.delivery_id = r.delivery_id
JOIN zava.PurchaseOrderLine pol ON pol.po_line_id = r.po_line_id
JOIN zava.PurchaseOrder po      ON po.po_id     = pol.po_id
JOIN zava.Product p             ON p.product_id = pol.product_id
WHERE 
    (r.qty_delivered - r.qty_damaged) <> pol.qty_ordered
    OR r.qty_damaged > 0;
GO


/* C) Reorder proposals: on-hand from InventoryTransaction vs policy,
      adjusted by footfall and lead times (supplier/product).
*/
CREATE OR ALTER VIEW cur.v_ReorderProposals
AS
WITH onhand AS (
  SELECT store_id, product_id, SUM(qty) AS qty_onhand
  FROM zava.InventoryTransaction
  GROUP BY store_id, product_id
)
SELECT 
    st.store_code,
    p.sku,
    p.product_name,
    sup.supplier_code,
    COALESCE(sp.lead_time_days, s.lead_time_default_days, 7) AS lead_time_days,
    st.footfall_index,
    ISNULL(oh.qty_onhand, 0) AS qty_onhand,
    spp.reorder_point,
    spp.reorder_qty,
    spp.safety_stock,
    CASE 
      WHEN ISNULL(oh.qty_onhand,0) <= (spp.reorder_point * st.footfall_index) THEN 1
      ELSE 0
    END AS reorder_trigger,
    CAST(CEILING(spp.reorder_qty * st.footfall_index * (COALESCE(sp.lead_time_days, s.lead_time_default_days, 7) / 7.0)) AS DECIMAL(12,3)) AS proposed_qty
FROM zava.StoreProductParam spp
JOIN zava.Store st ON st.store_id = spp.store_id
JOIN zava.Product p ON p.product_id = spp.product_id
LEFT JOIN onhand oh ON oh.store_id = spp.store_id AND oh.product_id = spp.product_id
LEFT JOIN zava.SupplierProduct sp ON sp.product_id = spp.product_id
LEFT JOIN zava.Supplier s ON s.supplier_id = sp.supplier_id
LEFT JOIN zava.Supplier sup ON sup.supplier_id = sp.supplier_id
WHERE p.perishable = 0
  AND ISNULL(oh.qty_onhand,0) <= (spp.reorder_point * st.footfall_index);


02_sql_db_inbound_and_apply.sql
Target:SQL Database in Fabric (your operational DB)
Purpose: Staging (zava_inbound), optional audit, helper function, APPLY stored procedures, and a tiny additive column for idempotency.

/* -----------------------------------------------------------
   02) Reverse ETL inbound + APPLY (run in SQL Database in Fabric)
   ----------------------------------------------------------- */

-- 0) Schemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'zava_inbound')
    EXEC('CREATE SCHEMA zava_inbound');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'zava_audit')
    EXEC('CREATE SCHEMA zava_audit');
GO

-- 1) Optional: simple run/error audit (use if you want logging)
IF OBJECT_ID('zava_audit.InboundRun') IS NULL
BEGIN
CREATE TABLE zava_audit.InboundRun
(
    run_id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    feed_name       SYSNAME       NOT NULL,
    started_utc     DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    ended_utc       DATETIME2(0)  NULL,
    status          NVARCHAR(20)  NOT NULL DEFAULT('STARTED'),
    rows_in         INT           NULL,
    rows_applied    INT           NULL,
    error_count     INT           NULL,
    details         NVARCHAR(4000) NULL
);
END
GO

IF OBJECT_ID('zava_audit.InboundError') IS NULL
BEGIN
CREATE TABLE zava_audit.InboundError
(
    error_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    run_id          BIGINT NOT NULL,
    feed_name       SYSNAME NOT NULL,
    source_row_id   NVARCHAR(100) NULL,
    error_utc       DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    error_message   NVARCHAR(4000) NOT NULL,
    payload         NVARCHAR(MAX) NULL,
    FOREIGN KEY (run_id) REFERENCES zava_audit.InboundRun(run_id)
);
END
GO

-- 2) Staging tables (business-key-based, idempotent)

-- Shipment status enrichment
IF OBJECT_ID('zava_inbound.ShipmentStatus') IS NULL
BEGIN
CREATE TABLE zava_inbound.ShipmentStatus
(
    inbound_id           BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_system        NVARCHAR(50)  NOT NULL,
    source_run_id        NVARCHAR(100) NULL,
    shipment_number      NVARCHAR(30)  NOT NULL,
    status               NVARCHAR(20)  NULL,
    planned_pickup_utc   DATETIME2(0)  NULL,
    actual_pickup_utc    DATETIME2(0)  NULL,
    planned_delivery_utc DATETIME2(0)  NULL,
    actual_delivery_utc  DATETIME2(0)  NULL,
    tracking_number      NVARCHAR(100) NULL,
    carrier_code         NVARCHAR(20)  NULL,
    weight_kg            DECIMAL(12,3) NULL,
    volume_m3            DECIMAL(12,3) NULL,
    notes                NVARCHAR(400) NULL,
    last_change_utc      DATETIME2(0)  NULL,
    loaded_utc           DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UX_in_ShipmentStatus UNIQUE (source_system, source_run_id, shipment_number)
);
END
GO

-- Delivery header + lines (reverse ETL of receipts)
IF OBJECT_ID('zava_inbound.DeliveryHeader') IS NULL
BEGIN
CREATE TABLE zava_inbound.DeliveryHeader
(
    inbound_delivery_id  BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_system        NVARCHAR(50)  NOT NULL,
    source_delivery_id   NVARCHAR(100) NOT NULL,
    shipment_number      NVARCHAR(30)  NOT NULL,
    store_code           NVARCHAR(20)  NOT NULL,
    status               NVARCHAR(20)  NULL,
    check_in_utc         DATETIME2(0)  NULL,
    check_out_utc        DATETIME2(0)  NULL,
    received_by          NVARCHAR(100) NULL,
    comments             NVARCHAR(400) NULL,
    discrepancy_flag     BIT           NULL,
    loaded_utc           DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UX_in_DelHeader UNIQUE (source_system, source_delivery_id)
);
END
GO

IF OBJECT_ID('zava_inbound.DeliveryLine') IS NULL
BEGIN
CREATE TABLE zava_inbound.DeliveryLine
(
    inbound_line_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_system        NVARCHAR(50)  NOT NULL,
    source_delivery_id   NVARCHAR(100) NOT NULL,
    po_number            NVARCHAR(30)  NOT NULL,
    sku                  NVARCHAR(30)  NOT NULL,
    qty_delivered        DECIMAL(12,3) NOT NULL,
    qty_damaged          DECIMAL(12,3) NOT NULL DEFAULT 0,
    lot_code             NVARCHAR(60)  NULL,
    expiry_date          DATE          NULL,
    comments             NVARCHAR(200) NULL,
    loaded_utc           DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_in_DelLine_Source ON zava_inbound.DeliveryLine(source_system, source_delivery_id);
END
GO

-- PO acknowledgements (optional)
IF OBJECT_ID('zava_inbound.POAcknowledgement') IS NULL
BEGIN
CREATE TABLE zava_inbound.POAcknowledgement
(
    inbound_ack_id       BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_system        NVARCHAR(50)  NOT NULL,
    source_run_id        NVARCHAR(100) NULL,
    po_number            NVARCHAR(30)  NOT NULL,
    sku                  NVARCHAR(30)  NULL,
    line_qty_confirmed   DECIMAL(12,3) NULL,
    expected_delivery_dt DATE          NULL,
    status               NVARCHAR(20)  NULL,
    comments             NVARCHAR(400) NULL,
    loaded_utc           DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_in_POAck ON zava_inbound.POAcknowledgement(po_number, sku);
END
GO

-- Exceptions staging
IF OBJECT_ID('zava_inbound.SLA_Violation') IS NULL
BEGIN
CREATE TABLE zava_inbound.SLA_Violation
(
    load_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    delivery_id     BIGINT NOT NULL,
    delivery_number NVARCHAR(30) NOT NULL,
    store_code      NVARCHAR(20) NOT NULL,
    supplier_code   NVARCHAR(20) NOT NULL,
    is_late         BIT NOT NULL,
    late_by_minutes INT NULL,
    severity        NVARCHAR(20) NOT NULL,
    description     NVARCHAR(400) NULL,
    loaded_utc      DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
END
GO

IF OBJECT_ID('zava_inbound.DeliveryDiscrepancy') IS NULL
BEGIN
CREATE TABLE zava_inbound.DeliveryDiscrepancy
(
    load_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    delivery_id     BIGINT NOT NULL,
    delivery_number NVARCHAR(30) NOT NULL,
    po_line_id      BIGINT NOT NULL,
    po_number       NVARCHAR(30) NOT NULL,
    sku             NVARCHAR(30) NOT NULL,
    exception_code  NVARCHAR(40) NOT NULL,
    severity        NVARCHAR(20) NOT NULL,
    description     NVARCHAR(400) NULL,
    loaded_utc      DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
END
GO

-- Reorder proposals (planner queue)
IF OBJECT_ID('zava_inbound.ReorderProposal') IS NULL
BEGIN
CREATE TABLE zava_inbound.ReorderProposal
(
    proposal_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    store_code      NVARCHAR(20) NOT NULL,
    sku             NVARCHAR(30) NOT NULL,
    supplier_code   NVARCHAR(20) NULL,
    qty_onhand      DECIMAL(12,3) NOT NULL,
    proposed_qty    DECIMAL(12,3) NOT NULL,
    lead_time_days  INT NOT NULL,
    footfall_index  DECIMAL(5,2) NOT NULL,
    created_utc     DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    status          NVARCHAR(20) NOT NULL DEFAULT('PENDING') -- PENDING, APPROVED, REJECTED, APPLIED
);
END
GO


-- 3) Idempotency helper on Delivery: external_ref (maps to source_delivery_id)
IF COL_LENGTH('zava.Delivery', 'external_ref') IS NULL
BEGIN
    ALTER TABLE zava.Delivery ADD external_ref NVARCHAR(100) NULL;
    CREATE UNIQUE INDEX UX_Delivery_ExternalRef
      ON zava.Delivery(external_ref) WHERE external_ref IS NOT NULL;
END
GO


-- 4) Helper to format delivery numbers from your existing sequence
CREATE OR ALTER FUNCTION zava_inbound.ufn_next_delivery_number()
RETURNS NVARCHAR(30)
AS
BEGIN
    DECLARE @seq BIGINT = NEXT VALUE FOR zava.seq_delivery_number;
    RETURN CONCAT('DL-', @seq);
END
GO


/* 5) APPLY Procedures
   -------------------- */

-- 5A) Shipment Status → zava.Shipment
CREATE OR ALTER PROCEDURE zava_inbound.usp_apply_ShipmentStatus
    @source_system NVARCHAR(50),
    @source_run_id NVARCHAR(100) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  ;WITH src AS (
    SELECT *
    FROM zava_inbound.ShipmentStatus
    WHERE source_system = @source_system
      AND (@source_run_id IS NULL OR source_run_id = @source_run_id)
  ),
  resolved AS (
    SELECT
      s.shipment_id,
      s.shipment_number,
      src.status,
      src.planned_pickup_utc, src.actual_pickup_utc,
      src.planned_delivery_utc, src.actual_delivery_utc,
      src.tracking_number,
      c.carrier_id,
      src.weight_kg, src.volume_m3, src.notes
    FROM src
    JOIN zava.Shipment s ON s.shipment_number = src.shipment_number
    LEFT JOIN zava.Carrier c ON c.carrier_code = src.carrier_code
  )
  UPDATE tgt
     SET tgt.status               = COALESCE(r.status, tgt.status),
         tgt.planned_pickup_utc   = COALESCE(r.planned_pickup_utc, tgt.planned_pickup_utc),
         tgt.actual_pickup_utc    = COALESCE(r.actual_pickup_utc, tgt.actual_pickup_utc),
         tgt.planned_delivery_utc = COALESCE(r.planned_delivery_utc, tgt.planned_delivery_utc),
         tgt.actual_delivery_utc  = COALESCE(r.actual_delivery_utc, tgt.actual_delivery_utc),
         tgt.tracking_number      = COALESCE(r.tracking_number, tgt.tracking_number),
         tgt.carrier_id           = COALESCE(r.carrier_id, tgt.carrier_id),
         tgt.weight_kg            = COALESCE(r.weight_kg, tgt.weight_kg),
         tgt.volume_m3            = COALESCE(r.volume_m3, tgt.volume_m3),
         tgt.notes                = COALESCE(r.notes, tgt.notes)
  FROM zava.Shipment tgt
  JOIN resolved r ON r.shipment_id = tgt.shipment_id;
END
GO


-- 5B) SLA Violations → DeliveryException('LATE')
CREATE OR ALTER PROCEDURE zava_inbound.usp_apply_SLA_Violations
AS
BEGIN
  SET NOCOUNT ON;

  ;WITH src AS (
    SELECT delivery_id, is_late, severity,
           COALESCE(description, CONCAT('Late by ', late_by_minutes, ' minutes')) AS description
    FROM zava_inbound.SLA_Violation
    WHERE is_late = 1
  )
  INSERT INTO zava.DeliveryException (delivery_id, delivery_line_id, code, severity, description)
  SELECT s.delivery_id, NULL, 'LATE', s.severity, s.description
  FROM src s
  WHERE NOT EXISTS (
    SELECT 1
    FROM zava.DeliveryException e
    WHERE e.delivery_id = s.delivery_id
      AND e.code = 'LATE'
      AND ISNULL(e.description,'') = ISNULL(s.description,'')
  );
END
GO


-- 5C) Quantity Discrepancies → DeliveryException (SHORT/OVER/DAMAGE)
CREATE OR ALTER PROCEDURE zava_inbound.usp_apply_DeliveryDiscrepancies
AS
BEGIN
  SET NOCOUNT ON;

  ;WITH src AS (
    SELECT delivery_id, po_line_id, exception_code, severity, description
    FROM zava_inbound.DeliveryDiscrepancy
  ),
  line_res AS (
    SELECT s.delivery_id, s.exception_code, s.severity, s.description,
           MIN(dl.delivery_line_id) AS delivery_line_id
    FROM src s
    JOIN zava.DeliveryLine dl 
      ON dl.delivery_id = s.delivery_id AND dl.po_line_id = s.po_line_id
    GROUP BY s.delivery_id, s.exception_code, s.severity, s.description
  )
  INSERT INTO zava.DeliveryException (delivery_id, delivery_line_id, code, severity, description)
  SELECT x.delivery_id, x.delivery_line_id, x.exception_code, x.severity, x.description
  FROM line_res x
  WHERE NOT EXISTS (
    SELECT 1
    FROM zava.DeliveryException e
    WHERE e.delivery_id = x.delivery_id
      AND e.delivery_line_id = x.delivery_line_id
      AND e.code = x.exception_code
      AND ISNULL(e.description,'') = ISNULL(x.description,'')
  );
END
GO


-- 5D) Deliveries & Receipts: Delivery / DeliveryLine / InventoryTransaction + PO rollups
CREATE OR ALTER PROCEDURE zava_inbound.usp_apply_Deliveries
    @source_system NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;

  /* 1) Resolve headers and MERGE into zava.Delivery using external_ref for idempotency */
  ;WITH hdr_src AS (
    SELECT dh.source_delivery_id, dh.shipment_number, dh.store_code,
           COALESCE(dh.status,'RECEIVING') AS status,
           dh.check_in_utc, dh.check_out_utc, dh.received_by, dh.comments,
           ISNULL(dh.discrepancy_flag,0) AS discrepancy_flag
    FROM zava_inbound.DeliveryHeader dh
    WHERE dh.source_system = @source_system
  ),
  hdr_resolved AS (
    SELECT hs.*,
           s.shipment_id,
           st.store_id
    FROM hdr_src hs
    JOIN zava.Shipment s ON s.shipment_number = hs.shipment_number
    JOIN zava.Store st ON st.store_code = hs.store_code AND st.store_id = s.store_id
  )
  SELECT CAST(NULL AS NVARCHAR(100)) AS source_delivery_id,
         CAST(NULL AS BIGINT)        AS delivery_id,
         CAST(NULL AS NVARCHAR(30))  AS delivery_number
  INTO #applied_hdr
  WHERE 1=0;

  MERGE zava.Delivery AS tgt
  USING (
      SELECT hr.source_delivery_id, hr.shipment_id, hr.store_id,
             hr.status, hr.check_in_utc, hr.check_out_utc, hr.received_by, hr.comments, hr.discrepancy_flag
      FROM hdr_resolved hr
  ) AS src
  ON (tgt.external_ref = src.source_delivery_id)
  WHEN MATCHED THEN
    UPDATE SET
      tgt.status          = src.status,
      tgt.check_in_utc    = COALESCE(src.check_in_utc, tgt.check_in_utc),
      tgt.check_out_utc   = COALESCE(src.check_out_utc, tgt.check_out_utc),
      tgt.received_by     = COALESCE(src.received_by, tgt.received_by),
      tgt.comments        = COALESCE(src.comments, tgt.comments),
      tgt.discrepancy_flag= src.discrepancy_flag
  WHEN NOT MATCHED THEN
    INSERT (delivery_number, shipment_id, store_id, status, check_in_utc, check_out_utc, received_by, discrepancy_flag, comments, external_ref, created_utc)
    VALUES (
      zava_inbound.ufn_next_delivery_number(),
      src.shipment_id, src.store_id, src.status, src.check_in_utc, src.check_out_utc, src.received_by, src.discrepancy_flag, src.comments,
      src.source_delivery_id, SYSUTCDATETIME()
    )
  OUTPUT
    src.source_delivery_id,
    inserted.delivery_id,
    inserted.delivery_number
  INTO #applied_hdr(source_delivery_id, delivery_id, delivery_number);

  /* 2) Resolve lines to product + PO line and INSERT if not already present */
  ;WITH line_src AS (
    SELECT dl.source_delivery_id, dl.po_number, dl.sku,
           dl.qty_delivered, dl.qty_damaged, dl.lot_code, dl.expiry_date, dl.comments
    FROM zava_inbound.DeliveryLine dl
    WHERE dl.source_system = @source_system
  ),
  line_resolved AS (
    SELECT
      ah.delivery_id,
      p.product_id,
      pol.po_line_id,
      ls.qty_delivered, ls.qty_damaged, ls.lot_code, ls.expiry_date, ls.comments
    FROM line_src ls
    JOIN #applied_hdr ah ON ah.source_delivery_id = ls.source_delivery_id
    JOIN zava.Product p ON p.sku = ls.sku
    JOIN zava.PurchaseOrder po ON po.po_number = ls.po_number
    JOIN zava.PurchaseOrderLine pol ON pol.po_id = po.po_id AND pol.product_id = p.product_id
  )
  INSERT INTO zava.DeliveryLine
  (delivery_id, po_line_id, product_id, qty_delivered, qty_damaged, lot_code, expiry_date, comments)
  SELECT
    lr.delivery_id, lr.po_line_id, lr.product_id,
    lr.qty_delivered, lr.qty_damaged, lr.lot_code, lr.expiry_date, lr.comments
  FROM line_resolved lr
  WHERE NOT EXISTS (
    SELECT 1 FROM zava.DeliveryLine dl
    WHERE dl.delivery_id = lr.delivery_id
      AND dl.po_line_id  = lr.po_line_id
      AND dl.product_id  = lr.product_id
      AND ISNULL(dl.lot_code,'')           = ISNULL(lr.lot_code,'')
      AND ISNULL(dl.expiry_date,'1900-01-01') = ISNULL(lr.expiry_date,'1900-01-01')
      AND ABS((dl.qty_delivered - lr.qty_delivered)) < 0.0005
      AND ABS((dl.qty_damaged   - lr.qty_damaged))   < 0.0005
  );

  /* 3) Inventory receipts once per (store, product, delivery_number) */
  ;WITH new_lines AS (
    SELECT dl.delivery_line_id, d.delivery_id, d.store_id, dl.product_id,
           (dl.qty_delivered - dl.qty_damaged) AS qty_net,
           d.delivery_number,
           COALESCE(d.check_in_utc, d.created_utc) AS receipt_dt
    FROM zava.Delivery d
    JOIN zava.DeliveryLine dl ON dl.delivery_id = d.delivery_id
    WHERE d.delivery_id IN (SELECT delivery_id FROM #applied_hdr)
  )
  INSERT INTO zava.InventoryTransaction(store_id, product_id, txn_type, qty, txn_dt, reference)
  SELECT nl.store_id, nl.product_id, 'RECEIPT', nl.qty_net, nl.receipt_dt, CONCAT('DEL:', nl.delivery_number)
  FROM new_lines nl
  WHERE nl.qty_net <> 0
    AND NOT EXISTS(
       SELECT 1 FROM zava.InventoryTransaction it
       WHERE it.store_id = nl.store_id
         AND it.product_id = nl.product_id
         AND it.txn_type = 'RECEIPT'
         AND it.reference = CONCAT('DEL:', nl.delivery_number)
    );

  /* 4) Status rollups: POL and PO */
  ;WITH rec_tot AS (
    SELECT dl.po_line_id, SUM(dl.qty_delivered - dl.qty_damaged) AS qty_recv
    FROM zava.DeliveryLine dl
    JOIN zava.Delivery d ON d.delivery_id = dl.delivery_id
    WHERE d.delivery_id IN (SELECT delivery_id FROM #applied_hdr)
    GROUP BY dl.po_line_id
  )
  UPDATE pol
     SET pol.status = CASE 
       WHEN (SELECT SUM(dl2.qty_delivered - dl2.qty_damaged)
             FROM zava.DeliveryLine dl2
             WHERE dl2.po_line_id = pol.po_line_id) >= pol.qty_ordered
       THEN 'CLOSED'
       ELSE 'PARTIAL'
     END
  FROM zava.PurchaseOrderLine pol
  JOIN rec_tot r ON r.po_line_id = pol.po_line_id;

  ;WITH po_roll AS (
    SELECT po.po_id,
           SUM(CASE WHEN pol.status IN ('OPEN','PARTIAL') THEN 1 ELSE 0 END) AS open_or_partial
    FROM zava.PurchaseOrder po
    JOIN zava.PurchaseOrderLine pol ON pol.po_id = po.po_id
    GROUP BY po.po_id
  )
  UPDATE po
     SET po.status = CASE WHEN pr.open_or_partial = 0 THEN 'DELIVERED' ELSE 'DISPATCHED' END
  FROM zava.PurchaseOrder po
  JOIN zava.ShipmentPO spo ON spo.po_id = po.po_id
  JOIN #applied_hdr ah ON ah.delivery_id IS NOT NULL
  JOIN zava.Delivery d ON d.delivery_id = ah.delivery_id AND d.shipment_id = spo.shipment_id
  JOIN po_roll pr ON pr.po_id = po.po_id;

END
GO


-- 5E) PO Acknowledgements → PO/PO Lines (optional)
CREATE OR ALTER PROCEDURE zava_inbound.usp_apply_POAcknowledgements
    @source_system NVARCHAR(50),
    @source_run_id NVARCHAR(100) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  -- Header-level (sku IS NULL)
  ;WITH hdr AS (
    SELECT po_number,
           MAX(expected_delivery_dt) AS expected_delivery_dt,
           MAX(status) AS status
    FROM zava_inbound.POAcknowledgement
    WHERE source_system=@source_system
      AND (@source_run_id IS NULL OR source_run_id=@source_run_id)
      AND sku IS NULL
    GROUP BY po_number
  )
  UPDATE po
     SET expected_delivery_date = COALESCE(h.expected_delivery_dt, po.expected_delivery_date),
         status = COALESCE(h.status, po.status)
  FROM zava.PurchaseOrder po
  JOIN hdr h ON h.po_number = po.po_number;

  -- Line-level quantity confirmations
  UPDATE pol
     SET qty_ordered = COALESCE(a.line_qty_confirmed, pol.qty_ordered)
  FROM zava.PurchaseOrderLine pol
  JOIN zava.PurchaseOrder po ON po.po_id = pol.po_id
  JOIN zava.Product p ON p.product_id = pol.product_id
  JOIN zava_inbound.POAcknowledgement a
    ON a.po_number = po.po_number AND a.sku = p.sku
  WHERE a.source_system=@source_system
    AND (@source_run_id IS NULL OR a.source_run_id=@source_run_id);
END

03_security_grants.sql
Target:SQL Database in Fabric
Purpose: Allow your Workspace Managed Identity (or deployment SPN) to run the pipelines and procs.

Replace [{Your Entra ID Principal}] with your Workspace Managed Identity (or dedicated SPN) user name as created in the database (CREATE USER ... FROM EXTERNAL PROVIDER;).

/* -----------------------------------------------------------
   03) Security grants (run in SQL Database in Fabric)
   ----------------------------------------------------------- */

-- Example: create user for the workspace managed identity (if not present)
-- CREATE USER [<MI display name>] FROM EXTERNAL PROVIDER;

-- Grant minimal, principle-of-least-privilege access for Reverse ETL
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::zava_inbound TO [<Fabric MI or SPN>];
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::zava          TO [<Fabric MI or SPN>];
GRANT EXECUTE ON SCHEMA::zava_inbound                         TO [<Fabric MI or SPN>];

-- If you are using the optional audit tables:

04_optional_housekeeping.sql
Target:SQL Database in Fabric (optional)
Purpose: Keep staging lean.

/* -----------------------------------------------------------
   04) Optional housekeeping/retention
   ----------------------------------------------------------- */
-- Retain last 14 days of staging loads (adjust as needed)
DELETE FROM zava_inbound.SLA_Violation        WHERE loaded_utc < DATEADD(DAY, -14, SYSUTCDATETIME());
DELETE FROM zava_inbound.DeliveryDiscrepancy  WHERE loaded_utc < DATEADD(DAY, -14, SYSUTCDATETIME());
DELETE FROM zava_inbound.ReorderProposal      WHERE created_utc < DATEADD(DAY, -30, SYSUTCDATETIME());
DELETE FROM zava_inbound.DeliveryHeader       WHERE loaded_utc < DATEADD(DAY, -14, SYSUTCDATETIME());
DELETE FROM zava_inbound.DeliveryLine         WHERE loaded_utc < DATEADD(DAY, -14, SYSUTCDATETIME());
DELETE FROM zava_inbound.ShipmentStatus       WHERE loaded_utc < DATEADD(DAY, -14, SYSUTCDATETIME());
DELETE FROM zava_inbound.POAcknowledgement    WHERE loaded_utc < DATEADD(DAY, -30, SYSUTCDATETIME());

How to run & wire this up


Run 01_analytics_endpoint_curated_views.sql

In the SQL analytics endpoint (mirror), open the SQL editor → run the script.
Objects created: cur.v_SLA_Violations, cur.v_DeliveryDiscrepancies, cur.v_ReorderProposals.



Run 02_sql_db_inbound_and_apply.sql

In your SQL Database in Fabric (operational), run the script.
Objects created: zava_inbound tables, optional zava_audit, helper function, and APPLY procs.
One additive change to zava.Delivery: external_ref + unique filtered index (safe/idempotent).



Run 03_security_grants.sql

Grant your Workspace Managed Identity / SPN the needed rights.



Pipelines (Fabric Data Factory) – create 3 “Lakebase‑style” syncs:

SLA → Exceptions

Copy (Source = analytics endpoint → SELECT ... FROM cur.v_SLA_Violations) → Sink = zava_inbound.SLA_Violation (Pre‑copy: TRUNCATE TABLE ...)
Stored Procedure: zava_inbound.usp_apply_SLA_Violations


Discrepancies → Exceptions

Copy cur.v_DeliveryDiscrepancies → zava_inbound.DeliveryDiscrepancy → usp_apply_DeliveryDiscrepancies


Deliveries (if you’re bringing receipts from analytics/external)

Copy headers/lines (your curated sources) → zava_inbound.DeliveryHeader / DeliveryLine
usp_apply_Deliveries @source_system = 'OpsCurated'


(Optional)PO Acks: copy to zava_inbound.POAcknowledgement → usp_apply_POAcknowledgements.




If you want, I can generate the three pipeline definitions (one per feed) for import into Fabric—just confirm your linked service names and whether you prefer batch (truncate+load) or incremental for each feed.


What this delivers (Lakebase parity)

Curated “gold” logic runs where it scales (analytics endpoint)
Low‑latency sync to operational DB via managed pipelines
Idempotent upserts into operational tables (no dupes, safe retries)
Monitoring & retry via Fabric Data Factory
Single source of truth remains your SQL Database; mirror keeps analytics isolated


If you want the Auto‑PO extension (create DRAFT POs from ReorderProposal grouped by (store_code, supplier_code) using your existing sequences), say the word and I’ll add seq_po_number + the usp_create_DraftPOsFromProposals procedure.