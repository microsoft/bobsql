/* =======================================================================
   Zava Coffee — POS Schema for SQL Database in Microsoft Fabric
   Author: Bob + Copilot
   Purpose: POS OLTP with reliable outbox to Supply Chain (Azure SQL MI)
   ======================================================================= */

------------------------------------------------------------
-- 0) Housekeeping & Sequences
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'zava')
    EXEC('CREATE SCHEMA zava');
GO

-- Friendly business key sequences (optional)
CREATE SEQUENCE zava.seq_order_number    AS BIGINT START WITH 100000 INCREMENT BY 1;
CREATE SEQUENCE zava.seq_receipt_number  AS BIGINT START WITH 200000 INCREMENT BY 1;
CREATE SEQUENCE zava.seq_customer_number AS BIGINT START WITH 300000 INCREMENT BY 1;
GO

------------------------------------------------------------
-- 1) Reference enumerations / lookup tables
------------------------------------------------------------
CREATE TABLE zava.TenderType (
    tender_type_code NVARCHAR(20) NOT NULL PRIMARY KEY, -- CASH,CARD,GIFTCARD,VOUCHER,OTHER
    description      NVARCHAR(100) NOT NULL
);
INSERT INTO zava.TenderType VALUES
(N'CASH',N'Cash'),(N'CARD',N'Payment Card'),(N'GIFTCARD',N'Gift Card'),
(N'VOUCHER',N'Voucher/Coupon'),(N'OTHER',N'Other');

CREATE TABLE zava.FulfillmentType (
    fulfillment_type_code NVARCHAR(20) NOT NULL PRIMARY KEY, -- DINE_IN,TAKEAWAY,PICKUP
    description           NVARCHAR(100) NOT NULL
);
INSERT INTO zava.FulfillmentType VALUES
(N'DINE_IN',N'Dine-in'),(N'TAKEAWAY',N'Takeaway'),(N'PICKUP',N'Pickup');

CREATE TABLE zava.PrepStation (
    prep_station_id INT IDENTITY(1,1) PRIMARY KEY,
    station_code    NVARCHAR(30) NOT NULL UNIQUE,  -- ESPRESSO_BAR, COLD_BAR, KITCHEN
    station_name    NVARCHAR(100) NOT NULL
);

CREATE TABLE zava.TaxCategory (
    tax_category_id INT IDENTITY(1,1) PRIMARY KEY,
    code            NVARCHAR(30) NOT NULL UNIQUE,  -- FOOD, BEVERAGE, MERCH, ZERO
    description     NVARCHAR(200) NULL
);

-- Per-store tax rates (simplified)
CREATE TABLE zava.TaxRate (
    tax_rate_id      INT IDENTITY(1,1) PRIMARY KEY,
    store_id         INT NOT NULL,
    tax_category_id  INT NOT NULL,
    rate             DECIMAL(6,4) NOT NULL, -- 0.0825 = 8.25%
    effective_from   DATE NOT NULL,
    effective_to     DATE NULL,
    CONSTRAINT CHK_TaxRate_Range CHECK (rate >= 0 AND rate <= 1)
);
GO

------------------------------------------------------------
-- 2) Reference copies from Supply Chain (reverse ETL maintained)
--    Enforce POS FKs against these local copies.
------------------------------------------------------------
CREATE TABLE zava.RefStore (
    store_id   INT PRIMARY KEY,             -- matches Supply Chain store_id
    store_code NVARCHAR(20) NOT NULL UNIQUE,
    store_name NVARCHAR(100) NOT NULL,
    status     NVARCHAR(20)  NOT NULL       -- OPEN, CLOSED, etc.
);

CREATE TABLE zava.RefProduct (
    product_id     INT PRIMARY KEY,         -- matches Supply Chain product_id
    sku            NVARCHAR(30) NOT NULL UNIQUE,
    product_name   NVARCHAR(200) NOT NULL,
    uom            NVARCHAR(20)  NOT NULL,  -- kg, L, pcs, etc.
    perishable     BIT NOT NULL,
    shelf_life_days INT NULL
);
GO

------------------------------------------------------------
-- 3) Staff, Devices, Assignments
------------------------------------------------------------
CREATE TABLE zava.Staff (
    staff_id   INT IDENTITY(1,1) PRIMARY KEY,
    staff_code NVARCHAR(30) NOT NULL UNIQUE,
    full_name  NVARCHAR(100) NOT NULL,
    role       NVARCHAR(30)  NOT NULL,      -- BARISTA, MANAGER, etc.
    pin_hash   VARBINARY(64) NULL,          -- store only hashes
    active     BIT NOT NULL DEFAULT(1),
    rv         ROWVERSION
);

CREATE TABLE zava.Device (
    device_id      INT IDENTITY(1,1) PRIMARY KEY,
    device_code    NVARCHAR(50) NOT NULL UNIQUE,  -- e.g., POS-001, KIOSK-02
    device_type    NVARCHAR(20) NOT NULL CHECK (device_type IN ('POS','KIOSK','KDS')),
    os_name        NVARCHAR(40) NULL,
    model          NVARCHAR(60) NULL,
    registered_utc DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    active         BIT NOT NULL DEFAULT(1)
);

CREATE TABLE zava.DeviceAssignment (
    device_assignment_id INT IDENTITY(1,1) PRIMARY KEY,
    device_id     INT NOT NULL,
    store_id      INT NOT NULL,
    assigned_from DATETIME2(0) NOT NULL,
    assigned_to   DATETIME2(0) NULL,
    is_primary_pos BIT NOT NULL DEFAULT(0),
    CONSTRAINT FK_DeviceAssignment_Device FOREIGN KEY (device_id) REFERENCES zava.Device(device_id),
    CONSTRAINT FK_DeviceAssignment_Store  FOREIGN KEY (store_id)  REFERENCES zava.RefStore(store_id)
);
CREATE INDEX IX_DeviceAssignment_StoreActive ON zava.DeviceAssignment(store_id, assigned_to);
GO

------------------------------------------------------------
-- 4) Menu, Modifiers, Pricing, Routing
------------------------------------------------------------
CREATE TABLE zava.MenuItem (
    menu_item_id           INT IDENTITY(1,1) PRIMARY KEY,
    item_code              NVARCHAR(30) NOT NULL UNIQUE,  -- LATTE-M, CROISSANT
    item_name              NVARCHAR(120) NOT NULL,
    category               NVARCHAR(50)  NOT NULL,        -- Beverage, Bakery, Merch
    product_id             INT NULL,                      -- packaged goods (1:1)
    tax_category_id        INT NOT NULL,
    default_prep_station_id INT NULL,
    active                 BIT NOT NULL DEFAULT(1),
    CONSTRAINT FK_MenuItem_Product      FOREIGN KEY (product_id)      REFERENCES zava.RefProduct(product_id),
    CONSTRAINT FK_MenuItem_TaxCategory  FOREIGN KEY (tax_category_id) REFERENCES zava.TaxCategory(tax_category_id),
    CONSTRAINT FK_MenuItem_PrepStation  FOREIGN KEY (default_prep_station_id) REFERENCES zava.PrepStation(prep_station_id)
);

CREATE TABLE zava.ModifierGroup (
    modifier_group_id INT IDENTITY(1,1) PRIMARY KEY,
    group_code        NVARCHAR(30) NOT NULL UNIQUE, -- SIZE, MILK, SYRUP
    group_name        NVARCHAR(100) NOT NULL,
    required          BIT NOT NULL DEFAULT(0),
    min_select        INT NOT NULL DEFAULT(0),
    max_select        INT NOT NULL DEFAULT(1)
);

CREATE TABLE zava.ModifierOption (
    modifier_option_id INT IDENTITY(1,1) PRIMARY KEY,
    modifier_group_id  INT NOT NULL,
    option_code        NVARCHAR(30) NOT NULL,
    option_name        NVARCHAR(100) NOT NULL,
    price_delta_eur    DECIMAL(12,2) NOT NULL DEFAULT(0),
    sort_order         INT NOT NULL DEFAULT(0),
    active             BIT NOT NULL DEFAULT(1),
    CONSTRAINT UQ_ModifierOption UNIQUE (modifier_group_id, option_code),
    CONSTRAINT FK_ModifierOption_Group FOREIGN KEY (modifier_group_id) REFERENCES zava.ModifierGroup(modifier_group_id)
);

CREATE TABLE zava.MenuItemModifierGroup (
    menu_item_id      INT NOT NULL,
    modifier_group_id INT NOT NULL,
    required          BIT NOT NULL,
    min_select        INT NOT NULL,
    max_select        INT NOT NULL,
    PRIMARY KEY (menu_item_id, modifier_group_id),
    CONSTRAINT FK_MIMG_MenuItem FOREIGN KEY (menu_item_id) REFERENCES zava.MenuItem(menu_item_id),
    CONSTRAINT FK_MIMG_Group    FOREIGN KEY (modifier_group_id) REFERENCES zava.ModifierGroup(modifier_group_id)
);

CREATE TABLE zava.PriceList (
    price_list_id  INT IDENTITY(1,1) PRIMARY KEY,
    list_name      NVARCHAR(100) NOT NULL,
    store_id       INT NULL,                  -- NULL = global
    channel        NVARCHAR(20) NOT NULL DEFAULT('ANY'), -- POS,KIOSK,ONLINE,ANY
    priority       INT NOT NULL DEFAULT(100), -- lower wins
    effective_from DATETIME2(0) NOT NULL,
    effective_to   DATETIME2(0) NULL,
    CONSTRAINT FK_PriceList_Store FOREIGN KEY (store_id) REFERENCES zava.RefStore(store_id)
);

CREATE TABLE zava.PriceListItem (
    price_list_id  INT NOT NULL,
    menu_item_id   INT NOT NULL,
    base_price_eur DECIMAL(12,2) NOT NULL,
    tax_included   BIT NOT NULL DEFAULT(0),
    PRIMARY KEY (price_list_id, menu_item_id),
    CONSTRAINT FK_PLI_PriceList FOREIGN KEY (price_list_id) REFERENCES zava.PriceList(price_list_id),
    CONSTRAINT FK_PLI_MenuItem  FOREIGN KEY (menu_item_id)  REFERENCES zava.MenuItem(menu_item_id)
);

CREATE TABLE zava.MenuItemRoute (
    menu_item_id    INT NOT NULL PRIMARY KEY,
    prep_station_id INT NOT NULL,
    CONSTRAINT FK_MenuItemRoute_Item    FOREIGN KEY (menu_item_id)    REFERENCES zava.MenuItem(menu_item_id),
    CONSTRAINT FK_MenuItemRoute_Station FOREIGN KEY (prep_station_id) REFERENCES zava.PrepStation(prep_station_id)
);
GO

------------------------------------------------------------
-- 5) Recipes (sales → inventory consumption)
------------------------------------------------------------
CREATE TABLE zava.MenuItemRecipe (
    menu_item_id INT NOT NULL,
    product_id   INT NOT NULL,
    qty_per_unit DECIMAL(12,3) NOT NULL, -- in product UOM
    PRIMARY KEY (menu_item_id, product_id),
    CONSTRAINT FK_Recipe_Item    FOREIGN KEY (menu_item_id) REFERENCES zava.MenuItem(menu_item_id),
    CONSTRAINT FK_Recipe_Product FOREIGN KEY (product_id)   REFERENCES zava.RefProduct(product_id),
    CONSTRAINT CHK_Recipe_Qty CHECK (qty_per_unit >= 0)
);

CREATE TABLE zava.ModifierOptionRecipe (
    modifier_option_id INT NOT NULL,
    product_id         INT NOT NULL,
    qty_delta_per_unit DECIMAL(12,3) NOT NULL, -- can be + or -
    PRIMARY KEY (modifier_option_id, product_id),
    CONSTRAINT FK_MOR_Option  FOREIGN KEY (modifier_option_id) REFERENCES zava.ModifierOption(modifier_option_id),
    CONSTRAINT FK_MOR_Product FOREIGN KEY (product_id)         REFERENCES zava.RefProduct(product_id)
);
GO

------------------------------------------------------------
-- 6) Customers & Loyalty
------------------------------------------------------------
CREATE TABLE zava.Customer (
    customer_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    customer_number NVARCHAR(30) NOT NULL UNIQUE
        CONSTRAINT DF_Customer_Number DEFAULT ('C-' + RIGHT(REPLICATE('0',6)+CAST(NEXT VALUE FOR zava.seq_customer_number AS NVARCHAR(20)),6)),
    first_name      NVARCHAR(80) NULL,
    last_name       NVARCHAR(80) NULL,
    email           NVARCHAR(200) NULL,
    phone           NVARCHAR(40) NULL,
    marketing_opt_in BIT NOT NULL DEFAULT(0),
    created_utc     DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE zava.LoyaltyAccount (
    loyalty_account_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    customer_id        BIGINT NOT NULL,
    points_balance     INT NOT NULL DEFAULT(0),
    created_utc        DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Loyalty_Customer FOREIGN KEY (customer_id) REFERENCES zava.Customer(customer_id)
);

CREATE TABLE zava.LoyaltyTransaction (
    loyalty_txn_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    loyalty_account_id BIGINT NOT NULL,
    order_id           BIGINT NULL,   -- link to sale
    points_delta       INT NOT NULL,
    reason             NVARCHAR(100) NULL,
    created_utc        DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_LoyaltyTxn_Account FOREIGN KEY (loyalty_account_id) REFERENCES zava.LoyaltyAccount(loyalty_account_id)
);
GO

------------------------------------------------------------
-- 7) Sales Orders, Lines, Modifiers, Taxes
------------------------------------------------------------
CREATE TABLE zava.SalesOrder (
    order_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_number     NVARCHAR(30) NOT NULL UNIQUE
        CONSTRAINT DF_SalesOrder_Number DEFAULT ('SO-' + RIGHT(REPLICATE('0',6)+CAST(NEXT VALUE FOR zava.seq_order_number AS NVARCHAR(20)),6)),
    store_id         INT NOT NULL,
    device_id        INT NOT NULL,
    staff_id         INT NULL,           -- NULL for kiosk
    customer_id      BIGINT NULL,
    channel          NVARCHAR(20) NOT NULL CHECK (channel IN ('POS','KIOSK','ONLINE')),
    fulfillment_type NVARCHAR(20) NOT NULL, -- DINE_IN,TAKEAWAY,PICKUP
    status           NVARCHAR(20) NOT NULL DEFAULT('OPEN'), -- OPEN,SUBMITTED,IN_PROGRESS,READY,COMPLETED,CANCELLED,REFUNDED
    created_utc      DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    submitted_utc    DATETIME2(0) NULL,
    completed_utc    DATETIME2(0) NULL,
    pickup_name      NVARCHAR(80) NULL,
    notes            NVARCHAR(200) NULL,
    subtotal_eur     DECIMAL(14,2) NULL,
    discount_eur     DECIMAL(14,2) NOT NULL DEFAULT(0),
    tax_eur          DECIMAL(14,2) NULL,
    tip_eur          DECIMAL(14,2) NOT NULL DEFAULT(0),
    total_eur        DECIMAL(14,2) NULL,
    rv               ROWVERSION,
    CONSTRAINT FK_SO_Store      FOREIGN KEY (store_id)  REFERENCES zava.RefStore(store_id),
    CONSTRAINT FK_SO_Device     FOREIGN KEY (device_id) REFERENCES zava.Device(device_id),
    CONSTRAINT FK_SO_Staff      FOREIGN KEY (staff_id)  REFERENCES zava.Staff(staff_id),
    CONSTRAINT FK_SO_Customer   FOREIGN KEY (customer_id) REFERENCES zava.Customer(customer_id),
    CONSTRAINT FK_SO_Fulfill    FOREIGN KEY (fulfillment_type) REFERENCES zava.FulfillmentType(fulfillment_type_code)
);
CREATE INDEX IX_SalesOrder_StoreStatus ON zava.SalesOrder(store_id, status, created_utc);

CREATE TABLE zava.SalesOrderLine (
    order_line_id       BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id            BIGINT NOT NULL,
    line_no             INT NOT NULL,
    menu_item_id        INT NOT NULL,
    qty                 DECIMAL(9,3) NOT NULL,
    unit_price_eur      DECIMAL(12,2) NOT NULL,
    discount_eur        DECIMAL(12,2) NOT NULL DEFAULT(0),
    line_subtotal_eur   AS (qty * unit_price_eur - discount_eur) PERSISTED,
    tax_amount_eur      DECIMAL(12,2) NOT NULL DEFAULT(0),
    line_total_eur      AS (line_subtotal_eur + tax_amount_eur) PERSISTED,
    notes               NVARCHAR(200) NULL,
    prep_station_id     INT NULL,  -- override routing
    CONSTRAINT FK_SOL_Order     FOREIGN KEY (order_id)     REFERENCES zava.SalesOrder(order_id),
    CONSTRAINT FK_SOL_MenuItem  FOREIGN KEY (menu_item_id) REFERENCES zava.MenuItem(menu_item_id),
    CONSTRAINT FK_SOL_Prep      FOREIGN KEY (prep_station_id) REFERENCES zava.PrepStation(prep_station_id),
    CONSTRAINT UX_SOL_Order_LineNo UNIQUE (order_id, line_no)
);

CREATE TABLE zava.SalesOrderLineModifier (
    order_line_modifier_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_line_id          BIGINT NOT NULL,
    modifier_option_id     INT NOT NULL,
    price_delta_eur        DECIMAL(12,2) NOT NULL DEFAULT(0),
    qty                    DECIMAL(9,3) NOT NULL DEFAULT(1),
    amount_eur             AS (qty * price_delta_eur) PERSISTED,
    CONSTRAINT FK_SOLM_Line   FOREIGN KEY (order_line_id)      REFERENCES zava.SalesOrderLine(order_line_id),
    CONSTRAINT FK_SOLM_Option FOREIGN KEY (modifier_option_id) REFERENCES zava.ModifierOption(modifier_option_id)
);
CREATE INDEX IX_SOLM_Line ON zava.SalesOrderLineModifier(order_line_id);

CREATE TABLE zava.SalesOrderLineTax (
    order_line_tax_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_line_id     BIGINT NOT NULL,
    tax_category_id   INT NOT NULL,
    tax_rate          DECIMAL(6,4) NOT NULL,
    tax_amount_eur    DECIMAL(12,2) NOT NULL,
    CONSTRAINT FK_SOLT_Line        FOREIGN KEY (order_line_id)    REFERENCES zava.SalesOrderLine(order_line_id),
    CONSTRAINT FK_SOLT_TaxCategory FOREIGN KEY (tax_category_id)  REFERENCES zava.TaxCategory(tax_category_id)
);
CREATE INDEX IX_SOLT_Line ON zava.SalesOrderLineTax(order_line_id);
GO

------------------------------------------------------------
-- 8) KDS (Kitchen Display) Tickets & Items
------------------------------------------------------------
CREATE TABLE zava.KdsTicket (
    kds_ticket_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id      BIGINT NOT NULL,
    status        NVARCHAR(20) NOT NULL DEFAULT('QUEUED'), -- QUEUED,IN_PROGRESS,READY,PICKED_UP
    displayed_utc DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_utc   DATETIME2(0) NULL,
    CONSTRAINT FK_KDST_Order FOREIGN KEY (order_id) REFERENCES zava.SalesOrder(order_id)
);
CREATE INDEX IX_KDST_Status ON zava.KdsTicket(status, displayed_utc);

CREATE TABLE zava.KdsItem (
    kds_item_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    kds_ticket_id   BIGINT NOT NULL,
    order_line_id   BIGINT NOT NULL,
    prep_station_id INT NOT NULL,
    status          NVARCHAR(20) NOT NULL DEFAULT('QUEUED'),
    CONSTRAINT FK_KDSI_Ticket FOREIGN KEY (kds_ticket_id) REFERENCES zava.KdsTicket(kds_ticket_id),
    CONSTRAINT FK_KDSI_Line   FOREIGN KEY (order_line_id)  REFERENCES zava.SalesOrderLine(order_line_id),
    CONSTRAINT FK_KDSI_Station FOREIGN KEY (prep_station_id) REFERENCES zava.PrepStation(prep_station_id)
);
CREATE INDEX IX_KDSI_StationStatus ON zava.KdsItem(prep_station_id, status);
GO

------------------------------------------------------------
-- 9) Payments & Receipts
------------------------------------------------------------
CREATE TABLE zava.Payment (
    payment_id       BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id         BIGINT NOT NULL,
    tender_type_code NVARCHAR(20) NOT NULL,
    status           NVARCHAR(20) NOT NULL DEFAULT('CAPTURED'), -- AUTHORIZED,CAPTURED,VOIDED,REFUNDED,DECLINED
    amount_eur       DECIMAL(14,2) NOT NULL,
    tip_amount_eur   DECIMAL(14,2) NOT NULL DEFAULT(0),
    currency_code    CHAR(3) NOT NULL DEFAULT('EUR'),
    provider         NVARCHAR(50) NULL,
    provider_txn_id  NVARCHAR(100) NULL,
    auth_utc         DATETIME2(0) NULL,
    capture_utc      DATETIME2(0) NULL,
    card_brand       NVARCHAR(20) NULL,
    card_last4       CHAR(4) NULL,
    card_exp_month   TINYINT NULL,
    card_exp_year    SMALLINT NULL,
    cash_given_eur   DECIMAL(14,2) NULL,
    cash_change_eur  DECIMAL(14,2) NULL,
    created_utc      DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Payment_Order      FOREIGN KEY (order_id)         REFERENCES zava.SalesOrder(order_id),
    CONSTRAINT FK_Payment_TenderType FOREIGN KEY (tender_type_code) REFERENCES zava.TenderType(tender_type_code),
    CONSTRAINT CHK_Payment_Positive  CHECK (amount_eur >= 0 AND tip_amount_eur >= 0)
);
CREATE INDEX IX_Payment_Order ON zava.Payment(order_id);

CREATE TABLE zava.Receipt (
    receipt_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id        BIGINT NOT NULL,
    receipt_number  NVARCHAR(30) NOT NULL UNIQUE
        CONSTRAINT DF_Receipt_Number DEFAULT ('RC-' + RIGHT(REPLICATE('0',6)+CAST(NEXT VALUE FOR zava.seq_receipt_number AS NVARCHAR(20)),6)),
    receipt_url     NVARCHAR(400) NULL,
    receipt_blob    VARBINARY(MAX) NULL,
    created_utc     DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Receipt_Order FOREIGN KEY (order_id) REFERENCES zava.SalesOrder(order_id),
    CONSTRAINT CHK_Receipt_Storage CHECK (
        (receipt_url IS NOT NULL AND receipt_blob IS NULL) OR
        (receipt_url IS NULL AND receipt_blob IS NOT NULL)
    )
);
GO

------------------------------------------------------------
-- 10) POS Operational Inventory + Outbox (reliable handoff)
------------------------------------------------------------
CREATE TABLE zava.InventoryTransaction (
    inv_txn_id       BIGINT IDENTITY(1,1) PRIMARY KEY,
    store_id         INT NOT NULL,
    product_id       INT NOT NULL,
    txn_type         NVARCHAR(20) NOT NULL CHECK (txn_type IN ('SALE','ADJUST','RECEIPT')),
    qty              DECIMAL(12,3) NOT NULL,  -- SALE negative; RECEIPT positive
    txn_dt           DATETIME2(0)  NOT NULL,
    reference        NVARCHAR(100) NULL,      -- e.g., 'SO:SO-100123'
    source_system    NVARCHAR(20)  NOT NULL DEFAULT('POS'),
    source_event_id  UNIQUEIDENTIFIER NULL,   -- idempotency correlation with outbox
    CONSTRAINT FK_InvTxn_Store   FOREIGN KEY (store_id)   REFERENCES zava.RefStore(store_id),
    CONSTRAINT FK_InvTxn_Product FOREIGN KEY (product_id) REFERENCES zava.RefProduct(product_id)
);
CREATE INDEX IX_InvTxn_StoreProductDate ON zava.InventoryTransaction(store_id, product_id, txn_dt)
    INCLUDE (qty, txn_type, reference, source_event_id);

-- Reliable outbox for cross-system propagation (to Azure SQL MI)
CREATE TABLE zava.OutboxEvents (
    event_id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    event_type         NVARCHAR(50)     NOT NULL,        -- e.g., 'Inventory.SalePosted'
    aggregate_type     NVARCHAR(50)     NOT NULL,        -- 'SalesOrder'
    aggregate_id       BIGINT           NOT NULL,        -- order_id
    store_id           INT              NOT NULL,
    occurred_utc       DATETIME2(0)     NOT NULL DEFAULT SYSUTCDATETIME(),
    payload_json       NVARCHAR(MAX)    NOT NULL,        -- serialized inventory rows
    status             NVARCHAR(20)     NOT NULL DEFAULT 'PENDING',  -- PENDING|SENT|FAILED|DEAD
    attempts           INT              NOT NULL DEFAULT 0,
    next_attempt_utc   DATETIME2(0)     NULL
);
CREATE INDEX IX_Outbox_StatusNext ON zava.OutboxEvents(status, next_attempt_utc, occurred_utc);
GO

------------------------------------------------------------
-- 11) Helpful indexes for POS workloads
------------------------------------------------------------
CREATE INDEX IX_MenuItem_ActiveCategory ON zava.MenuItem(active, category);
CREATE INDEX IX_PriceList_Resolve ON zava.PriceList(store_id, channel, effective_from, effective_to, priority);
CREATE INDEX IX_PriceListItem_Item ON zava.PriceListItem(menu_item_id);
GO

------------------------------------------------------------
-- 12) Posting procedure:
--     From a COMPLETED order, compute ingredient usage (recipes+modifiers),
--     insert POS InventoryTransaction (SALE, negative), and emit an Outbox event.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE zava.usp_PostSalesOrderToInventoryAndOutbox
    @order_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @order_status NVARCHAR(20), @store_id INT, @order_number NVARCHAR(30);
    SELECT @order_status = status, @store_id = store_id, @order_number = order_number
    FROM zava.SalesOrder WHERE order_id = @order_id;

    IF @order_status IS NULL
    BEGIN
        RAISERROR('Order %I64d not found.', 16, 1, @order_id);
        RETURN;
    END

    IF @order_status NOT IN ('COMPLETED','REFUNDED')  -- adjust as desired
    BEGIN
        RAISERROR('Order %I64d is not in a postable status (COMPLETED/REFUNDED).', 16, 1, @order_id);
        RETURN;
    END

    -- Idempotency: if we've already inserted inventory rows for this order, skip
    IF EXISTS (SELECT 1 FROM zava.InventoryTransaction WHERE reference = CONCAT('SO:', @order_number))
        RETURN;

    DECLARE @event_id UNIQUEIDENTIFIER = NEWID();
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;

    -- Compute base item consumption
    ;WITH BaseLines AS (
        SELECT sol.menu_item_id, sol.qty
        FROM zava.SalesOrderLine AS sol
        WHERE sol.order_id = @order_id
    ),
    ItemCons AS (
        SELECT r.product_id, SUM(b.qty * r.qty_per_unit) AS qty_used
        FROM BaseLines AS b
        JOIN zava.MenuItemRecipe AS r ON r.menu_item_id = b.menu_item_id
        GROUP BY r.product_id
    ),
    ModCons AS (
        SELECT mor.product_id,
               SUM(solm.qty * mor.qty_delta_per_unit * sol.qty) AS qty_delta
        FROM zava.SalesOrderLine AS sol
        JOIN zava.SalesOrderLineModifier AS solm ON solm.order_line_id = sol.order_line_id
        JOIN zava.ModifierOptionRecipe AS mor ON mor.modifier_option_id = solm.modifier_option_id
        WHERE sol.order_id = @order_id
        GROUP BY mor.product_id
    ),
    TotalCons AS (
        SELECT COALESCE(ic.product_id, mc.product_id) AS product_id,
               COALESCE(ic.qty_used, 0) + COALESCE(mc.qty_delta, 0) AS qty_total
        FROM ItemCons ic
        FULL OUTER JOIN ModCons mc ON mc.product_id = ic.product_id
    ),
    FinalCons AS (
        SELECT product_id, qty_total
        FROM TotalCons
        WHERE qty_total > 0
    )
    -- Insert POS inventory transactions (SALE = negative)
    INSERT zava.InventoryTransaction (store_id, product_id, txn_type, qty, txn_dt, reference, source_event_id)
    SELECT @store_id,
           fc.product_id,
           N'SALE',
           -fc.qty_total,
           @now,
           CONCAT('SO:', @order_number),
           @event_id
    FROM FinalCons AS fc;

    -- Serialize payload for outbox (array of line items with product & qty)
    DECLARE @payload NVARCHAR(MAX) =
    (
        SELECT
            @order_id        AS order_id,
            @order_number    AS order_number,
            @store_id        AS store_id,
            @now             AS txn_dt,
            'SALE'           AS txn_type,
            'POS'            AS source_system,
            @event_id        AS source_event_id,
            (SELECT fc.product_id,
                    CAST(-fc.qty_total AS DECIMAL(12,3)) AS qty,  -- negative in target
                    CONCAT('SO:', @order_number) AS reference
             FROM FinalCons fc
             FOR JSON PATH) AS items
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT zava.OutboxEvents (event_id, event_type, aggregate_type, aggregate_id, store_id, occurred_utc, payload_json, status, attempts, next_attempt_utc)
    VALUES (@event_id, N'Inventory.SalePosted', N'SalesOrder', @order_id, @store_id, @now, @payload, N'PENDING', 0, NULL);

    COMMIT TRAN;
END;
GO

------------------------------------------------------------
-- 13) Optional: view for current inventory snapshot (fast lookups)
------------------------------------------------------------
CREATE OR ALTER VIEW zava.v_CurrentInventory
WITH SCHEMABINDING
AS
SELECT it.store_id, it.product_id, SUM(it.qty) AS qty_on_hand, COUNT_BIG(*) AS row_count
FROM zava.InventoryTransaction AS it
GROUP BY it.store_id, it.product_id;
GO
CREATE UNIQUE CLUSTERED INDEX CUX_v_CurrentInventory ON zava.v_CurrentInventory(store_id, product_id);
