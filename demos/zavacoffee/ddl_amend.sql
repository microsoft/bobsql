------------------------------------------------------------
-- 0) Sequences for friendly business keys
------------------------------------------------------------
CREATE SEQUENCE zava.seq_shipment_number AS BIGINT START WITH 500000 INCREMENT BY 1;
CREATE SEQUENCE zava.seq_delivery_number AS BIGINT START WITH 700000 INCREMENT BY 1;
GO

------------------------------------------------------------
-- 1) Optional reference: Carrier
-- Suppliers may self-deliver; carrier is optional on shipments.
------------------------------------------------------------
CREATE TABLE zava.Carrier
(
    carrier_id       INT IDENTITY(1,1) PRIMARY KEY,
    carrier_code     NVARCHAR(20) NOT NULL UNIQUE,
    carrier_name     NVARCHAR(200) NOT NULL,
    mode             NVARCHAR(20)  NULL, -- Road, Courier, Air (rare), etc.
    contact_email    NVARCHAR(200) NULL,
    tracking_url_tpl NVARCHAR(400) NULL   -- e.g., 'https://track.example.com/{0}'
);
GO

------------------------------------------------------------
-- 2) Shipment: Supplier → Store, may consolidate multiple POs
------------------------------------------------------------
CREATE TABLE zava.Shipment
(
    shipment_id           BIGINT IDENTITY(1,1) PRIMARY KEY,
    shipment_number       NVARCHAR(30) NOT NULL UNIQUE,  -- e.g., 'SH-500001'
    supplier_id           INT NOT NULL,
    store_id              INT NOT NULL,                  -- ship-to store
    carrier_id            INT NULL,
    tracking_number       NVARCHAR(100) NULL,
    incoterms             NVARCHAR(20) NULL,             -- copied from supplier if needed
    status                NVARCHAR(20) NOT NULL DEFAULT('CREATED'),
    created_utc           DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    planned_pickup_utc    DATETIME2(0) NULL,
    planned_delivery_utc  DATETIME2(0) NULL,
    actual_pickup_utc     DATETIME2(0) NULL,
    actual_delivery_utc   DATETIME2(0) NULL,
    weight_kg             DECIMAL(12,3) NULL,
    volume_m3             DECIMAL(12,3) NULL,
    notes                 NVARCHAR(400) NULL,
    CONSTRAINT FK_Shipment_Supplier FOREIGN KEY (supplier_id) REFERENCES zava.Supplier(supplier_id),
    CONSTRAINT FK_Shipment_Store    FOREIGN KEY (store_id)    REFERENCES zava.Store(store_id),
    CONSTRAINT FK_Shipment_Carrier  FOREIGN KEY (carrier_id)  REFERENCES zava.Carrier(carrier_id),
    CONSTRAINT CHK_Shipment_Status  CHECK (status IN ('CREATED','DISPATCHED','IN_TRANSIT','OUT_FOR_DELIVERY','DELIVERED','CANCELLED'))
);
GO

------------------------------------------------------------
-- 3) Bridge: Shipment ↔ PurchaseOrder (many-to-many, but often 1:many)
------------------------------------------------------------
CREATE TABLE zava.ShipmentPO
(
    shipment_id BIGINT NOT NULL,
    po_id       BIGINT NOT NULL,
    PRIMARY KEY (shipment_id, po_id),
    CONSTRAINT FK_ShipmentPO_Shipment FOREIGN KEY (shipment_id) REFERENCES zava.Shipment(shipment_id),
    CONSTRAINT FK_ShipmentPO_PO       FOREIGN KEY (po_id)       REFERENCES zava.PurchaseOrder(po_id)
);
GO

------------------------------------------------------------
-- 4) Delivery header: store receiving event for a shipment
------------------------------------------------------------
CREATE TABLE zava.Delivery
(
    delivery_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    delivery_number     NVARCHAR(30) NOT NULL UNIQUE,    -- e.g., 'DL-700001'
    shipment_id         BIGINT NOT NULL,
    store_id            INT NOT NULL,
    status              NVARCHAR(20) NOT NULL DEFAULT('SCHEDULED'), -- SCHEDULED, ARRIVED, RECEIVING, COMPLETED, PARTIAL, REJECTED
    check_in_utc        DATETIME2(0) NULL,
    check_out_utc       DATETIME2(0) NULL,
    received_by         NVARCHAR(100) NULL,              -- staff name/ID
    discrepancy_flag    BIT NOT NULL DEFAULT(0),
    comments            NVARCHAR(400) NULL,
    created_utc         DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Delivery_Shipment FOREIGN KEY (shipment_id) REFERENCES zava.Shipment(shipment_id),
    CONSTRAINT FK_Delivery_Store    FOREIGN KEY (store_id)    REFERENCES zava.Store(store_id),
    CONSTRAINT CHK_Delivery_Status  CHECK (status IN ('SCHEDULED','ARRIVED','RECEIVING','COMPLETED','PARTIAL','REJECTED'))
);
GO

------------------------------------------------------------
-- 5) Delivery lines: what actually arrived, with condition
------------------------------------------------------------
CREATE TABLE zava.DeliveryLine
(
    delivery_line_id   BIGINT IDENTITY(1,1) PRIMARY KEY,
    delivery_id        BIGINT NOT NULL,
    po_line_id         BIGINT NOT NULL,          -- links back to ordered line
    product_id         INT NOT NULL,             -- redundant for convenience (FK-enforced)
    qty_delivered      DECIMAL(12,3) NOT NULL,   -- physically delivered quantity
    qty_damaged        DECIMAL(12,3) NOT NULL DEFAULT (0),
    lot_code           NVARCHAR(60) NULL,
    expiry_date        DATE NULL,                -- for perishables
    comments           NVARCHAR(200) NULL,
    CONSTRAINT FK_DelLine_Delivery  FOREIGN KEY (delivery_id) REFERENCES zava.Delivery(delivery_id),
    CONSTRAINT FK_DelLine_POL       FOREIGN KEY (po_line_id)  REFERENCES zava.PurchaseOrderLine(po_line_id),
    CONSTRAINT FK_DelLine_Product   FOREIGN KEY (product_id)  REFERENCES zava.Product(product_id),
    CONSTRAINT CHK_DelLine_Qty      CHECK (qty_delivered >= 0 AND qty_damaged >= 0)
    -- Note: product consistency with PO line is enforced in proc logic.
);
GO

------------------------------------------------------------
-- 6) Delivery exceptions (optional, by header or line)
------------------------------------------------------------
CREATE TABLE zava.DeliveryException
(
    exception_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    delivery_id      BIGINT NOT NULL,
    delivery_line_id BIGINT NULL,
    code             NVARCHAR(40) NOT NULL,      -- SHORT, OVER, DAMAGE, TEMP_BREACH, LATE, OTHER
    severity         NVARCHAR(20) NOT NULL,      -- INFO, WARN, CRITICAL
    description      NVARCHAR(400) NULL,
    recorded_utc     DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_DelEx_Delivery FOREIGN KEY (delivery_id) REFERENCES zava.Delivery(delivery_id),
    CONSTRAINT FK_DelEx_DeliveryLine FOREIGN KEY (delivery_line_id) REFERENCES zava.DeliveryLine(delivery_line_id)
);
GO

------------------------------------------------------------
-- 7) Proof of Delivery artifacts (e.g., signature/photo)
------------------------------------------------------------
CREATE TABLE zava.ProofOfDelivery
(
    pod_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    delivery_id   BIGINT NOT NULL,
    pod_type      NVARCHAR(20) NOT NULL,         -- SIGNATURE, PHOTO, NOTE, SCAN
    pod_url       NVARCHAR(400) NULL,            -- if stored externally (Blob/SharePoint)
    pod_blob      VARBINARY(MAX) NULL,           -- optional inline storage
    recorded_utc  DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_PoD_Delivery FOREIGN KEY (delivery_id) REFERENCES zava.Delivery(delivery_id),
    CONSTRAINT CHK_PoD_Type CHECK (pod_type IN ('SIGNATURE','PHOTO','NOTE','SCAN'))
);
GO

------------------------------------------------------------
-- 8) Indexes
------------------------------------------------------------
CREATE INDEX IX_Shipment_Status         ON zava.Shipment(status, planned_delivery_utc);
CREATE INDEX IX_Shipment_StoreSupplier  ON zava.Shipment(store_id, supplier_id);
CREATE INDEX IX_ShipmentPO_PO           ON zava.ShipmentPO(po_id);

CREATE INDEX IX_Delivery_Shipment       ON zava.Delivery(shipment_id);
CREATE INDEX IX_Delivery_Status         ON zava.Delivery(status, check_in_utc);

CREATE INDEX IX_DeliveryLine_POL        ON zava.DeliveryLine(po_line_id);
CREATE INDEX IX_DeliveryLine_Product    ON zava.DeliveryLine(product_id);
GO
