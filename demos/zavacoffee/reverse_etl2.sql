/* Great question, Bob. A clean “reverse ETL” demo in Fabric—using your SQL Database in Fabric (ops) → SQL analytics endpoint (read‑only mirror) → Dataflows Gen2 → back to the operational database or another operational system—is to push replenishment recommendations from analytics back into a table your app or a stored proc can act on (e.g., auto‑creating POs).
Below is a concrete, end‑to‑end example you can copy/paste and run. */

/* What we’ll show
Goal: Compute Replenishment Proposals from mirrored tables, then write them back to an operational table (zava.ReplenishmentProposal) using Dataflows Gen2 (reverse ETL).
Why this is a good demo:

It uses the read‑onlySQL analytics endpoint as the analytics source, which is automatically kept in sync by mirroring. [Mirroring...(preview)], [fabric-doc....md at ...]
It shows Dataflows Gen2 writing to an operational destination (Fabric SQL database or Azure SQL), which is a supported data destination for Dataflows Gen2. [Dataflow G...d settings]
It optionally chains a pipeline step (call a stored proc) after the dataflow refresh to turn proposals into POs—nice “activation” touch. [Move and t...oft Fabric]


Quick reminders

SQL analytics endpoint is read‑only for data, but you can create views / inline TVFs / stored procedures for query logic there. [Microsoft...Fabric ...]
Mirroring from SQL Database in Fabric to OneLake/SQL analytics endpoint happens automatically and continuously. [Mirroring...(preview)], [fabric-doc....md at ...] */

/* 0) Create the operational destination table
Create this in the operational SQL Database in Fabric (not in the analytics endpoint). You can put it in the same zava schema so it also mirrors and becomes visible analytically later. */

-- Operational write target (reverse ETL landing)
IF OBJECT_ID('zava.ReplenishmentProposal','U') IS NOT NULL
    DROP TABLE zava.ReplenishmentProposal;
GO
CREATE TABLE zava.ReplenishmentProposal
(
    proposal_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    asof_utc           DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    store_id           INT          NOT NULL,
    product_id         INT          NOT NULL,
    current_stock      DECIMAL(12,3) NOT NULL,
    reorder_point      DECIMAL(12,3) NOT NULL,
    safety_stock       DECIMAL(12,3) NOT NULL,
    recommended_qty    DECIMAL(12,3) NOT NULL,
    supplier_id        INT           NULL,
    unit_price_eur     DECIMAL(12,2) NULL,
    comment            NVARCHAR(200) NULL
);
GO

/* 1) Author helper views in the SQL analytics endpoint
Because the analytics endpoint is read‑only for data, we encapsulate logic in views there. You can do this in the analytics endpoint’s SQL editor.

The analytics endpoint allows creating views/SPs over the mirrored Delta tables. [Microsoft...Fabric ...] */

/* 1a. Current stock per store/product */
-- Analytics endpoint (read-only data, but DDL for views is allowed)
CREATE OR ALTER VIEW dbo.vw_CurrentStock AS
SELECT 
    it.store_id,
    it.product_id,
    SUM(CASE it.txn_type 
            WHEN 'RECEIPT' THEN it.qty 
            WHEN 'SALE'    THEN -it.qty 
            ELSE it.qty
        END) AS current_stock
FROM zava.InventoryTransaction it
GROUP BY it.store_id, it.product_id;

/* 1b. Join with store/product parameters & supplier pricing */
CREATE OR ALTER VIEW dbo.vw_ReplenishmentBase AS
SELECT
    p.store_id,
    p.product_id,
    cs.current_stock,
    p.reorder_point,
    p.safety_stock,
    sp.supplier_id,
    sp.price_eur AS unit_price_eur
FROM zava.StoreProductParam p
LEFT JOIN dbo.vw_CurrentStock cs 
    ON cs.store_id = p.store_id AND cs.product_id = p.product_id
LEFT JOIN zava.SupplierProduct sp 
    ON sp.product_id = p.product_id;


/* 1c. Compute the recommendation */
CREATE OR ALTER VIEW dbo.vw_ReplenishmentRecommendation AS
SELECT
    store_id,
    product_id,
    ISNULL(current_stock, 0) AS current_stock,
    reorder_point,
    safety_stock,
    supplier_id,
    unit_price_eur,
    CASE 
        WHEN ISNULL(current_stock,0) < (reorder_point + safety_stock)
        THEN (reorder_point + safety_stock) - ISNULL(current_stock,0)
        ELSE 0
    END AS recommended_qty
FROM dbo.vw_ReplenishmentBase;

/* 2) Build the Dataflow Gen2 (reverse ETL)
Source: the SQL analytics endpoint (select dbo.vw_ReplenishmentRecommendation).
Destination: the Fabric SQL database (operational) table zava.ReplenishmentProposal.
Steps (Power Query Online UI):


Create Dataflow Gen2 → Get Data from the SQL analytics endpoint in your workspace; pick the dbo.vw_ReplenishmentRecommendation view. (This endpoint is automatically maintained by mirroring for your SQL Database in Fabric.) [fabric-doc....md at ...]


Transform (optional)

Filter out recommended_qty = 0 rows (we only write “needs action”).
Add/format columns you want (e.g., comment).



Set Destination

Click Add data destination and choose Fabric SQL database. Supported destinations include Fabric SQL database, Fabric Warehouse, Lakehouse, Azure SQL, KQL DB, etc. [Dataflow G...d settings]
Use existing table, select zava.ReplenishmentProposal.
Update method:

Replace to keep only the latest snapshot of recommendations, or
Append to keep history (common in ops hand‑offs). (Replace/Append are supported update methods.) [Dataflow G...d settings]


Optionally set a default destination for the dataflow so future queries auto‑bind to the same target. [Dataflow G...oft Fabric]



Publish & schedule

Schedule the dataflow to refresh at your cadence (e.g., hourly) so ops always sees fresh proposals.




Notes & gotchas

Dataflows Gen2 destinations and managed mapping options (create new table vs. use existing; schema handling; replace vs append) are documented here. [Dataflow G...d settings]
If you target a Warehouse instead, staging must be enabled (UI will prompt). [Dataflow G...d settings]
For best performance, use query folding where possible and consider Fast Copy / staging patterns. [Best pract...aflow Gen2] */

/* 4) What you can show in the UI (demo flow)

Insert a few SALE/RECEIPTInventoryTransaction rows.
Show the SQL analytics endpoint view returning the current deltas almost immediately (mirroring in action). [Mirroring...(preview)]
Run the Dataflow Gen2 → show rows landing in zava.ReplenishmentProposal in the operational DB. [Dataflow G...d settings]
(Optional) Trigger the pipeline → stored proc writes POs and lines; your app (or a simple query) shows the new operational records. [Move and t...oft Fabric] */

/* 7) Why this is “textbook” reverse ETL in Fabric

Analytics layer → Ops layer loop: insights (low stock) go back to an operational table your app/workflows can act on.
Uses the SQL analytics endpoint properly as read‑only analytic source, decoupled from operational workloads. [Mirroring...(preview)]
Uses Dataflows Gen2 as a low‑code writer to operational systems (Fabric SQL DB / Azure SQL). [Dataflow G...d settings]
Can be orchestrated with Pipelines for end‑to‑end automation. [Move and t...oft Fabric]
Scales with folding / Fast Copy / staging guidance. [Best pract...aflow Gen2] */

/* Absolutely! Reverse ETL (Extract, Transform, Load) is the process of moving data from a data warehouse or data lake back into operational systems like CRMs, marketing platforms, or support tools. Here's a summary of the benefits in a typical scenario:

Scenario:
You have a centralized data warehouse (e.g., Azure Synapse, Snowflake, BigQuery) where all your customer, sales, and product data is aggregated. Your business teams use tools like Salesforce, HubSpot, or Zendesk to engage with customers.

Benefits of Reverse ETL:


Operationalizes Data for Business Teams

Makes rich, centralized data accessible in tools that sales, marketing, and support teams already use.
Enables real-time personalization, targeted campaigns, and proactive customer support.



Improves Decision-Making

Empowers frontline teams with up-to-date insights (e.g., customer lifetime value, churn risk) directly in their workflows.
Reduces reliance on data teams for manual exports or dashboards.



Enhances Customer Experience

Enables consistent and personalized interactions across channels.
For example, a support agent can see recent product usage or support history without switching tools.



Reduces Data Silos

Ensures that the same source of truth (the data warehouse) powers both analytics and operational systems.
Minimizes discrepancies between reporting and action.



Automates Workflows

Triggers actions based on data (e.g., send a Slack alert when a high-value customer churns).
Integrates with tools like Zapier or native automation in CRMs.



Accelerates Time-to-Value

Faster deployment of data-driven initiatives without building custom pipelines.
Tools like Hightouch, Census, or Azure Data Factory simplify the process.



*/

/* 1) Dataflow Gen2: ready‑to‑import definition (JSON)
What it does

Reads from a SQL view dbo.vw_Proposals (header + lines flattened).
Writes to your Fabric Warehouse table stg.ProposalFeed in Replace mode (idempotent staging).
Adds ingestion timestamp.


⚙️ Replace the placeholders:
<SQL_SERVER_NAME>, <SQL_DATABASE_NAME>, <FABRIC_WORKSPACE_ID>, <FABRIC_WAREHOUSE_ID>.
If your view/table names differ, adjust in the M and output settings accordingly. */

/* JSON (Dataflow Gen2)

Save as dataflow-gen2-proposals.json and import in Fabric: Dataflow Gen2 → New → Import from a JSON file. */

{
  "name": "DFG2 - Proposals → Warehouse Staging",
  "description": "Reads dbo.vw_Proposals and writes to Warehouse stg.ProposalFeed (Replace each run)",
  "definition": {
    "queries": [
      {
        "name": "stg_ProposalFeed",
        "query": "let\n  // --- Source: SQL View (flattened header + lines) ---\n  Source = Sql.Database(\"<SQL_SERVER_NAME>\", \"<SQL_DATABASE_NAME>\", [CreateNavigationProperties=false]),\n  Proposals = Source{[Schema=\"dbo\", Item=\"vw_Proposals\"]}[Data],\n\n  // --- Optional: type casts ---\n  Typed = Table.TransformColumnTypes(\n    Proposals,\n    {\n      {\"ProposalId\", Int64.Type},\n      {\"SupplierId\", Int64.Type},\n      {\"ProposalDate\", type date},\n      {\"Status\", type text},\n      {\"LineNumber\", Int64.Type},\n      {\"ProductId\", Int64.Type},\n      {\"Quantity\", type number},\n      {\"UnitPrice\", type number},\n      {\"CurrencyCode\", type text}\n    }\n  ),\n\n  // --- Add ingestion timestamp ---\n  WithIngestedAt = Table.AddColumn(Typed, \"IngestedAt\", each DateTimeZone.UtcNow(), type datetimezone)\n\nin\n  WithIngestedAt",
        "loadEnabled": true,
        "output": {
          "destinationType": "warehouse",
          "workspaceId": "<FABRIC_WORKSPACE_ID>",
          "itemId": "<FABRIC_WAREHOUSE_ID>",
          "schema": "stg",
          "table": "ProposalFeed",
          "writeDisposition": "replace"
        },
        "connectionReferences": {
          "sqlConnection": {
            "kind": "Sql",
            "path": "Sql/Database",
            "properties": {
              "server": "<SQL_SERVER_NAME>",
              "database": "<SQL_DATABASE_NAME>",
              "authenticationKind": "UsernamePassword" 
            }
          }
        }
      }
    ]
  },
  "refresh": {
    "enabled": true,
    "frequency": "Daily",
    "time": "02:00",
    "timeZone": "Central Standard Time"
  }
}

/* Notes & tips

Auth: If you use Azure AD/OAuth for SQL, switch authenticationKind accordingly; you’ll be prompted to bind credentials on first save.
Replace vs Append: For staging, replace is safest (CT-style pattern). If you need CDC, switch to append and add a watermark.
Alternate sink: If you prefer Lakehouse, change destinationType to "lakehouse" and set path: "Tables/ProposalFeed" (and remove schema/table). */

/* 2) Sample stored procedure: Upsert into PurchaseOrder / PurchaseOrderLine
Assumptions

The dataflow writes the flattened rows to stg.ProposalFeed.
One proposal → one PO header; multiple lines per proposal via LineNumber.
We use ExternalProposalId on PurchaseOrder to map back to ProposalId.
We run in a transaction, replace the staging each run, and delete missing lines for proposals in the batch (full-sync semantics).

You can tweak column names/types and constraints to match your real schema.
Optional: example target tables (if not already present) */

-- Header
IF OBJECT_ID('dbo.PurchaseOrder') IS NULL
BEGIN
  CREATE TABLE dbo.PurchaseOrder
  (
    PurchaseOrderId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    ExternalProposalId   BIGINT NOT NULL UNIQUE,  -- proposal key from source
    SupplierId           BIGINT NOT NULL,
    OrderDate            DATE   NOT NULL,
    Status               NVARCHAR(20) NOT NULL CONSTRAINT DF_PurchaseOrder_Status DEFAULT ('Open'),
    TotalAmount          DECIMAL(19,4) NULL,
    ModifiedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_PurchaseOrder_ModifiedAt DEFAULT (SYSUTCDATETIME())
  );
END;

-- Lines
IF OBJECT_ID('dbo.PurchaseOrderLine') IS NULL
BEGIN
  CREATE TABLE dbo.PurchaseOrderLine
  (
    PurchaseOrderLineId  BIGINT IDENTITY(1,1) PRIMARY KEY,
    PurchaseOrderId      BIGINT NOT NULL FOREIGN KEY REFERENCES dbo.PurchaseOrder(PurchaseOrderId),
    LineNumber           INT   NOT NULL,
    ProductId            BIGINT NOT NULL,
    Quantity             DECIMAL(19,4) NOT NULL,
    UnitPrice            DECIMAL(19,4) NOT NULL,
    LineAmount           AS (Quantity * UnitPrice) PERSISTED,
    ModifiedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_PurchaseOrderLine_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_PurchaseOrderLine UNIQUE (PurchaseOrderId, LineNumber)
  );
END;

-- Staging (dataflow target)
IF SCHEMA_ID('stg') IS NULL EXEC ('CREATE SCHEMA stg');
IF OBJECT_ID('stg.ProposalFeed') IS NULL
BEGIN
  CREATE TABLE stg.ProposalFeed
  (
    ProposalId     BIGINT NOT NULL,
    SupplierId     BIGINT NOT NULL,
    ProposalDate   DATE   NOT NULL,
    Status         NVARCHAR(20) NULL,
    LineNumber     INT   NOT NULL,
    ProductId      BIGINT NOT NULL,
    Quantity       DECIMAL(19,4) NOT NULL,
    UnitPrice      DECIMAL(19,4) NOT NULL,
    CurrencyCode   NVARCHAR(10) NULL,
    IngestedAt     DATETIME2(3) NOT NULL
  );
END;

/* Upsert stored procedure
This proc:

Aggregates headers from staging and MERGEs into PurchaseOrder.
Maps ProposalId → PurchaseOrderId.
MERGEs lines on (PurchaseOrderId, LineNumber).
Deletes lines not present in the latest staging for those proposals.
Optionally recomputes header TotalAmount. */

CREATE OR ALTER PROCEDURE dbo.usp_UpsertProposals
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  -- Use snapshot isolation if you have it enabled to reduce blocking:
  -- ALTER DATABASE CURRENT SET ALLOW_SNAPSHOT_ISOLATION ON;
  -- SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

  BEGIN TRAN;

  ----------------------------------------------------------------------
  -- 1) Upsert PO headers from current staging snapshot (replace mode)
  ----------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#Headers') IS NOT NULL DROP TABLE #Headers;
  SELECT
      pf.ProposalId,
      MIN(pf.SupplierId)      AS SupplierId,
      MIN(pf.ProposalDate)    AS OrderDate,
      COALESCE(MAX(pf.Status), 'Open') AS Status
  INTO #Headers
  FROM stg.ProposalFeed pf
  GROUP BY pf.ProposalId;

  -- Map of affected proposals for scoping line ops/deletes
  IF OBJECT_ID('tempdb..#AffectedProposals') IS NOT NULL DROP TABLE #AffectedProposals;
  SELECT ProposalId INTO #AffectedProposals FROM #Headers;

  -- Upsert headers
  MERGE dbo.PurchaseOrder AS tgt
  USING #Headers AS src
    ON tgt.ExternalProposalId = src.ProposalId
  WHEN MATCHED THEN
    UPDATE SET
      SupplierId = src.SupplierId,
      OrderDate  = src.OrderDate,
      Status     = src.Status,
      ModifiedAt = SYSUTCDATETIME()
  WHEN NOT MATCHED BY TARGET THEN
    INSERT (ExternalProposalId, SupplierId, OrderDate, Status)
    VALUES (src.ProposalId,       src.SupplierId, src.OrderDate, src.Status);

  ----------------------------------------------------------------------
  -- 2) Upsert PO lines
  ----------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#PoMap') IS NOT NULL DROP TABLE #PoMap;
  SELECT p.ExternalProposalId AS ProposalId, p.PurchaseOrderId
  INTO #PoMap
  FROM dbo.PurchaseOrder p
  JOIN #AffectedProposals ap ON ap.ProposalId = p.ExternalProposalId;

  -- Staging lines (scoped to affected proposals)
  IF OBJECT_ID('tempdb..#Lines') IS NOT NULL DROP TABLE #Lines;
  SELECT
      m.PurchaseOrderId,
      pf.LineNumber,
      pf.ProductId,
      pf.Quantity,
      pf.UnitPrice
  INTO #Lines
  FROM stg.ProposalFeed pf
  JOIN #PoMap m
    ON m.ProposalId = pf.ProposalId;

  -- Upsert lines (insert/update/delete missing)
  MERGE dbo.PurchaseOrderLine AS tgt
  USING #Lines AS src
    ON tgt.PurchaseOrderId = src.PurchaseOrderId
   AND tgt.LineNumber      = src.LineNumber
  WHEN MATCHED AND (tgt.ProductId <> src.ProductId
                 OR tgt.Quantity  <> src.Quantity
                 OR tgt.UnitPrice <> src.UnitPrice) THEN
    UPDATE SET
      ProductId  = src.ProductId,
      Quantity   = src.Quantity,
      UnitPrice  = src.UnitPrice,
      ModifiedAt = SYSUTCDATETIME()
  WHEN NOT MATCHED BY TARGET THEN
    INSERT (PurchaseOrderId, LineNumber, ProductId, Quantity, UnitPrice)
    VALUES (src.PurchaseOrderId, src.LineNumber, src.ProductId, src.Quantity, src.UnitPrice)
  WHEN NOT MATCHED BY SOURCE
       AND tgt.PurchaseOrderId IN (SELECT PurchaseOrderId FROM #PoMap) THEN
    DELETE;

  ----------------------------------------------------------------------
  -- 3) Recompute header totals (optional)
  ----------------------------------------------------------------------
  UPDATE p
  SET
      TotalAmount = x.TotalAmount,
      ModifiedAt  = SYSUTCDATETIME()
  FROM dbo.PurchaseOrder p
  JOIN (
      SELECT pol.PurchaseOrderId, SUM(pol.Quantity * pol.UnitPrice) AS TotalAmount
      FROM dbo.PurchaseOrderLine pol
      GROUP BY pol.PurchaseOrderId
  ) x ON x.PurchaseOrderId = p.PurchaseOrderId
  WHERE p.ExternalProposalId IN (SELECT ProposalId FROM #AffectedProposals);

  COMMIT;

  -- Optional: clear staging after successful run if you always REPLACE
  -- TRUNCATE TABLE stg.ProposalFeed;
END;

/* Indexing suggestions */

-- Helps header MERGE probe
CREATE UNIQUE INDEX IXU_PurchaseOrder_ExternalProposalId
  ON dbo.PurchaseOrder(ExternalProposalId);

-- Helps line MERGE match
CREATE UNIQUE INDEX IXU_PurchaseOrderLine_UQ
  ON dbo.PurchaseOrderLine(PurchaseOrderId, LineNumber);

/* End‑to‑end orchestration (optional)

Fabric pipeline with two activities:

Run Dataflow Gen2 (Replace stg.ProposalFeed).
Warehouse – SQL script to execute EXEC dbo.usp_UpsertProposals;.


Add alerts/logging on row counts and failures. */

/* Want me to tailor this?
I can:

Fill in the exact server/db/view names and your Warehouse IDs and hand you the final JSON + .sql.
Switch the dataflow sink to Lakehouse instead of Warehouse.
Change the stored proc to accept a table‑valued parameter or JSON payload instead of using staging.
Implement soft‑delete instead of hard deletes on missing lines.

If you share the exact view name + target table names (and whether you’re on Fabric Warehouse or Lakehouse), I’ll finalize and attach the files. */

-- 1. Insert a European store
INSERT INTO zava.Store (store_code, store_name, city, country, timezone, open_date)
VALUES ('ST-EU01', 'Zava Berlin', 'Berlin', 'Germany', 'Central European Standard Time', '2023-01-01');

-- 2. Insert a product
INSERT INTO zava.Product (sku, product_name, category, uom, perishable, shelf_life_days)
VALUES ('SKU-ESP-EU', 'Espresso Beans EU', 'Beans', 'kg', 0, 365);

-- 3. Insert a supplier
INSERT INTO zava.Supplier (supplier_code, supplier_name, category)
VALUES ('SUP-EU01', 'EuroBean Co.', 'Coffee');

-- 4. Link supplier to product
INSERT INTO zava.SupplierProduct (supplier_id, product_id, price_eur, pack_size, min_order_qty, lead_time_days)
SELECT s.supplier_id, p.product_id, 12.50, 1.0, 10.0, 5
FROM zava.Supplier s, zava.Product p
WHERE s.supplier_code = 'SUP-EU01' AND p.sku = 'SKU-ESP-EU';

-- 5. Set store product parameters with high reorder thresholds
INSERT INTO zava.StoreProductParam (store_id, product_id, reorder_point, reorder_qty, safety_stock, max_stock)
SELECT st.store_id, p.product_id, 60, 100, 30, 250
FROM zava.Store st, zava.Product p
WHERE st.store_code = 'ST-EU01' AND p.sku = 'SKU-ESP-EU';

-- 6. Insert a SALE transaction to simulate low stock
INSERT INTO zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt)
SELECT st.store_id, p.product_id, 'SALE', 15, SYSUTCDATETIME()
FROM zava.Store st, zava.Product p
WHERE st.store_code = 'ST-EU01' AND p.sku = 'SKU-ESP-EU';

-- Run the dataflow again and then this query

SELECT store_name, product_name, rp.recommended_qty, rp.current_stock, sup.supplier_name
FROM zava.ReplenishmentProposal rp
JOIN zava.Store s
ON s.store_id = rp.store_id
JOIN zava.Product p
ON p.product_id = rp.product_id
JOIN zava.Supplier sup
ON sup.supplier_id = rp.supplier_id
WHERE recommended_qty > 0;
GO