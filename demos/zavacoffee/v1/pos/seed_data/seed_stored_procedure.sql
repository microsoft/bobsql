/* =======================================================================
   Zava Coffee — POS Sample Data Seeder (Stored Procedure)
   Target: SQL Database in Microsoft Fabric (POS)
   Seeds baseline refs if missing; generates orders/lines/payments across
   all stores in zava.RefStore over a date window, with options.
   ======================================================================= */

IF OBJECT_ID('zava.usp_Seed_POS') IS NOT NULL
    DROP PROCEDURE zava.usp_Seed_POS;
GO

CREATE PROCEDURE zava.usp_Seed_POS
    @DaysBack                 int           = 21,     -- generate last N days (excludes today)
    @OrdersPerStorePerDay     int           = 450,    -- main volume knob
    @MaxLinesPerOrder         int           = 3,      -- 1..N lines per order
    @PctKiosk                 int           = 35,     -- % of orders via KIOSK
    @PctCustomerAttached      int           = 40,     -- % of orders with a known customer
    @DoPostInventoryAndOutbox bit           = 0,      -- 1 = call zava.usp_PostSalesOrderToInventoryAndOutbox per order
    @MinCustomers             int           = 10000,  -- seed up to this many customers if fewer exist
    @AutoSeedReferences       bit           = 1,      -- seed TenderType, FulfillmentType, TaxCategory, Staff, Device, Menu, Pricing, Customers if missing
    @SeedBatchTag             nvarchar(64)  = NULL    -- batch tag embedded in SalesOrder.notes
AS
BEGIN
    SET NOCOUNT ON;

    /* ---------- Validate basic pre-reqs ---------- */
    IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'zava')
    BEGIN
        RAISERROR('Schema [zava] not found. Create schema first.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.RefStore') AND type = 'U')
    BEGIN
        RAISERROR('Table [zava].[RefStore] not found. Reverse-ETL stores or create refs first.', 16, 1);
        RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM zava.RefStore)
    BEGIN
        RAISERROR('[zava].[RefStore] is empty. Reverse-ETL stores before seeding POS.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.RefProduct') AND type = 'U')
    BEGIN
        RAISERROR('Table [zava].[RefProduct] not found. Reverse-ETL products or create refs first.', 16, 1);
        RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM zava.RefProduct)
    BEGIN
        RAISERROR('[zava].[RefProduct] is empty. Reverse-ETL products before seeding POS.', 16, 1);
        RETURN;
    END

    /* ---------- Compute window & batch tag ---------- */
    DECLARE @StartDate date = DATEADD(DAY, -@DaysBack, CAST(SYSDATETIME() AS date));
    DECLARE @EndDate   date = DATEADD(DAY, -1,         CAST(SYSDATETIME() AS date));

    IF @SeedBatchTag IS NULL
        SET @SeedBatchTag = CONCAT('POSSEED_', CONVERT(char(8), SYSDATETIME(), 112), '_', REPLACE(CONVERT(char(8), SYSDATETIME(), 108),':',''));

    /* ======================================================================
       A) Optional: Seed baseline reference data if missing
       ====================================================================== */
    IF (@AutoSeedReferences = 1)
    BEGIN
        /* TenderType */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.TenderType') AND type='U')
            CREATE TABLE zava.TenderType (tender_type_code NVARCHAR(20) NOT NULL PRIMARY KEY, description NVARCHAR(100) NOT NULL);

        MERGE zava.TenderType AS tgt
        USING (VALUES
           (N'CASH',N'Cash'),(N'CARD',N'Payment Card'),(N'GIFTCARD',N'Gift Card'),
           (N'VOUCHER',N'Voucher/Coupon'),(N'OTHER',N'Other')
        ) AS src(code,descr)
        ON tgt.tender_type_code = src.code
        WHEN NOT MATCHED THEN INSERT(tender_type_code, description) VALUES(src.code, src.descr);

        /* FulfillmentType */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.FulfillmentType') AND type='U')
            CREATE TABLE zava.FulfillmentType (fulfillment_type_code NVARCHAR(20) NOT NULL PRIMARY KEY, description NVARCHAR(100) NOT NULL);

        MERGE zava.FulfillmentType AS tgt
        USING (VALUES
            (N'DINE_IN',N'Dine-in'),(N'TAKEAWAY',N'Takeaway'),(N'PICKUP',N'Pickup')
        ) AS src(code,descr)
        ON tgt.fulfillment_type_code = src.code
        WHEN NOT MATCHED THEN INSERT(fulfillment_type_code, description) VALUES(src.code, src.descr);

        /* TaxCategory */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.TaxCategory') AND type='U')
            CREATE TABLE zava.TaxCategory (tax_category_id INT IDENTITY(1,1) PRIMARY KEY, code NVARCHAR(30) NOT NULL UNIQUE, description NVARCHAR(200) NULL);

        MERGE zava.TaxCategory AS tgt
        USING (VALUES
            ('BEVERAGE','Beverages incl. coffee/tea'),
            ('FOOD','Bakery and food items'),
            ('MERCH','Merchandise / gifts'),
            ('ZERO','Zero-rated')
        ) AS src(code,descr)
        ON tgt.code = src.code
        WHEN NOT MATCHED THEN INSERT(code, description) VALUES(src.code, src.descr);

        /* TaxRate — simple per-store defaults if missing */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.TaxRate') AND type='U')
        BEGIN
            CREATE TABLE zava.TaxRate (
              tax_rate_id INT IDENTITY(1,1) PRIMARY KEY,
              store_id INT NOT NULL,
              tax_category_id INT NOT NULL,
              rate DECIMAL(6,4) NOT NULL,
              effective_from DATE NOT NULL,
              effective_to DATE NULL
            );
        END

        ;WITH s AS (
          SELECT store_id,
                 0.075 + (ABS(CHECKSUM(store_id, 1)) % 150) / 10000.0 AS rate_bev,
                 0.065 + (ABS(CHECKSUM(store_id, 2)) % 150) / 10000.0 AS rate_food,
                 0.080 + (ABS(CHECKSUM(store_id, 3)) % 150) / 10000.0 AS rate_merch
          FROM zava.RefStore
        )
        INSERT zava.TaxRate(store_id, tax_category_id, rate, effective_from)
        SELECT s.store_id, tc.tax_category_id,
               CASE tc.code WHEN 'BEVERAGE' THEN s.rate_bev
                            WHEN 'FOOD'     THEN s.rate_food
                            WHEN 'MERCH'    THEN s.rate_merch
                            ELSE 0.0 END,
               DATEFROMPARTS(YEAR(GETDATE())-1,1,1)
        FROM s
        JOIN zava.TaxCategory tc ON tc.code IN ('BEVERAGE','FOOD','MERCH')
        WHERE NOT EXISTS (
          SELECT 1 FROM zava.TaxRate tr
          WHERE tr.store_id = s.store_id AND tr.tax_category_id = tc.tax_category_id
        );

        /* Staff (if none exist globally, create a handful per store) */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.Staff') AND type='U')
            CREATE TABLE zava.Staff (
              staff_id INT IDENTITY(1,1) PRIMARY KEY,
              staff_code NVARCHAR(30) NOT NULL UNIQUE,
              full_name NVARCHAR(100) NOT NULL,
              role NVARCHAR(30) NOT NULL,
              pin_hash VARBINARY(64) NULL,
              active BIT NOT NULL DEFAULT(1),
              rv ROWVERSION
            );

        IF NOT EXISTS (SELECT 1 FROM zava.Staff)
        BEGIN
            ;WITH perstore AS (
              SELECT rs.store_id, n = 1 UNION ALL SELECT rs.store_id, 2 UNION ALL SELECT rs.store_id, 3 UNION ALL SELECT rs.store_id, 4
              FROM zava.RefStore rs
            )
            INSERT zava.Staff(staff_code, full_name, role, active)
            SELECT CONCAT('ST', RIGHT('000000'+CAST(ABS(CHECKSUM(store_id, n)) % 999999 + 1 AS varchar(6)),6)),
                   CONCAT(N'Barista ', store_id, N' #', n),
                   CASE WHEN n=4 THEN 'MANAGER' ELSE 'BARISTA' END,
                   1
            FROM perstore;
        END

        /* Device + DeviceAssignment (ensure at least one POS & KIOSK) */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.Device') AND type='U')
            CREATE TABLE zava.Device (
                device_id INT IDENTITY(1,1) PRIMARY KEY,
                device_code NVARCHAR(50) NOT NULL UNIQUE,
                device_type NVARCHAR(20) NOT NULL,
                os_name NVARCHAR(40) NULL,
                model NVARCHAR(60) NULL,
                registered_utc DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
                active BIT NOT NULL DEFAULT(1)
            );

        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.DeviceAssignment') AND type='U')
            CREATE TABLE zava.DeviceAssignment (
                device_assignment_id INT IDENTITY(1,1) PRIMARY KEY,
                device_id INT NOT NULL,
                store_id INT NOT NULL,
                assigned_from DATETIME2(0) NOT NULL,
                assigned_to DATETIME2(0) NULL,
                is_primary_pos BIT NOT NULL DEFAULT(0)
            );

        ;WITH d AS (
          SELECT rs.store_id, v.dt
          FROM zava.RefStore rs
          CROSS APPLY (VALUES ('POS'), ('KIOSK')) v(dt)
        )
        INSERT zava.Device(device_code, device_type, active)
        SELECT CONCAT(dt, '-', RIGHT('000000'+CAST(store_id AS varchar(6)),6)),
               dt, 1
        FROM d
        WHERE NOT EXISTS (
          SELECT 1 FROM zava.Device WHERE device_code = CONCAT(d.dt, '-', RIGHT('000000'+CAST(d.store_id AS varchar(6)),6))
        );

        -- (Optional) we can skip DeviceAssignment unless you want history; POS logic only needs Device table.

        /* Menu + Pricing (if none) + minimal Recipes */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.MenuItem') AND type='U')
        BEGIN
            CREATE TABLE zava.MenuItem (
                menu_item_id INT IDENTITY(1,1) PRIMARY KEY,
                item_code NVARCHAR(30) NOT NULL UNIQUE,
                item_name NVARCHAR(120) NOT NULL,
                category NVARCHAR(50) NOT NULL,
                product_id INT NULL,
                tax_category_id INT NOT NULL,
                default_prep_station_id INT NULL,
                active BIT NOT NULL DEFAULT(1)
            );
        END

        IF NOT EXISTS (SELECT 1 FROM zava.MenuItem)
        BEGIN
            DECLARE @tc_bev int = (SELECT tax_category_id FROM zava.TaxCategory WHERE code='BEVERAGE');
            DECLARE @tc_food int = (SELECT tax_category_id FROM zava.TaxCategory WHERE code='FOOD');
            DECLARE @tc_merch int = (SELECT tax_category_id FROM zava.TaxCategory WHERE code='MERCH');

            INSERT zava.MenuItem(item_code, item_name, category, product_id, tax_category_id, active) VALUES
            ('ESP-S',  N'Espresso (Single)',      'Beverage', NULL, @tc_bev, 1),
            ('ESP-D',  N'Espresso (Double)',      'Beverage', NULL, @tc_bev, 1),
            ('AMER-M', N'Americano (12 oz)',      'Beverage', NULL, @tc_bev, 1),
            ('LAT-S',  N'Latte (12 oz)',          'Beverage', NULL, @tc_bev, 1),
            ('LAT-M',  N'Latte (16 oz)',          'Beverage', NULL, @tc_bev, 1),
            ('CAP-M',  N'Cappuccino (12 oz)',     'Beverage', NULL, @tc_bev, 1),
            ('MOCH-M', N'Mocha (16 oz)',          'Beverage', NULL, @tc_bev, 1),
            ('CB-M',   N'Cold Brew (16 oz)',      'Beverage', NULL, @tc_bev, 1),
            ('ICELAT', N'Iced Latte (16 oz)',     'Beverage', NULL, @tc_bev, 1),
            ('TEA-H',  N'Hot Tea (12 oz)',        'Beverage', NULL, @tc_bev, 1),
            ('COCO-H', N'Hot Chocolate (12 oz)',  'Beverage', NULL, @tc_bev, 1),
            ('CROI',   N'Butter Croissant',       'Bakery',   NULL, @tc_food, 1),
            ('MUFF',   N'Blueberry Muffin',       'Bakery',   NULL, @tc_food, 1),
            ('BAGL',   N'Bagel',                  'Bakery',   NULL, @tc_food, 1),
            ('WATER',  N'Bottled Water',          'Merch',    NULL, @tc_merch,1),
            ('BEAN250',N'House Beans 250g',       'Merch',    NULL, @tc_merch,1),
            ('MUG',    N'Zava Ceramic Mug',       'Merch',    NULL, @tc_merch,1);
        END

        -- Pricing tables
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.PriceList') AND type='U')
        BEGIN
            CREATE TABLE zava.PriceList (
              price_list_id INT IDENTITY(1,1) PRIMARY KEY,
              list_name NVARCHAR(100) NOT NULL,
              store_id INT NULL,
              channel NVARCHAR(20) NOT NULL DEFAULT('ANY'),
              priority INT NOT NULL DEFAULT(100),
              effective_from DATETIME2(0) NOT NULL,
              effective_to DATETIME2(0) NULL
            );
        END
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.PriceListItem') AND type='U')
        BEGIN
            CREATE TABLE zava.PriceListItem (
              price_list_id INT NOT NULL,
              menu_item_id INT NOT NULL,
              base_price_eur DECIMAL(12,2) NOT NULL,
              tax_included BIT NOT NULL DEFAULT(0),
              PRIMARY KEY (price_list_id, menu_item_id)
            );
        END

        DECLARE @pl_id int = (SELECT TOP 1 price_list_id FROM zava.PriceList WHERE channel IN ('ANY','POS','KIOSK') ORDER BY priority, effective_from DESC);
        IF @pl_id IS NULL
        BEGIN
            INSERT zava.PriceList(list_name, store_id, channel, priority, effective_from, effective_to)
            VALUES (N'Global List', NULL, 'ANY', 10, DATEADD(DAY, -365, CAST(SYSDATETIME() AS date)), NULL);
            SET @pl_id = SCOPE_IDENTITY();

            INSERT zava.PriceListItem(price_list_id, menu_item_id, base_price_eur, tax_included)
            SELECT @pl_id, mi.menu_item_id,
                   CASE mi.item_code
                     WHEN 'ESP-S'  THEN 2.20 WHEN 'ESP-D'  THEN 2.80
                     WHEN 'AMER-M' THEN 3.20
                     WHEN 'LAT-S'  THEN 3.80 WHEN 'LAT-M'  THEN 4.30
                     WHEN 'CAP-M'  THEN 3.90
                     WHEN 'MOCH-M' THEN 4.50
                     WHEN 'CB-M'   THEN 4.20
                     WHEN 'ICELAT' THEN 4.30
                     WHEN 'TEA-H'  THEN 2.50
                     WHEN 'COCO-H' THEN 3.50
                     WHEN 'CROI'   THEN 2.60
                     WHEN 'MUFF'   THEN 2.80
                     WHEN 'BAGL'   THEN 2.40
                     WHEN 'WATER'  THEN 1.80
                     WHEN 'BEAN250'THEN 9.90
                     WHEN 'MUG'    THEN 12.00
                     ELSE 3.00 END,
                   0
            FROM zava.MenuItem mi;
        END

        /* Minimal Recipes for beverages (beans/milk/syrup/cup/lid placeholders) */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.MenuItemRecipe') AND type='U')
            CREATE TABLE zava.MenuItemRecipe (menu_item_id INT NOT NULL, product_id INT NOT NULL, qty_per_unit DECIMAL(12,3) NOT NULL, PRIMARY KEY(menu_item_id, product_id));

        -- Pick five arbitrary RefProduct ids deterministically as ingredients
        DECLARE @p_beans int = (SELECT TOP 1 product_id FROM zava.RefProduct ORDER BY product_id);
        DECLARE @p_milk  int = (SELECT TOP 1 product_id FROM zava.RefProduct ORDER BY product_id OFFSET 1 ROWS);
        DECLARE @p_syr   int = (SELECT TOP 1 product_id FROM zava.RefProduct ORDER BY product_id OFFSET 2 ROWS);
        DECLARE @p_cups  int = (SELECT TOP 1 product_id FROM zava.RefProduct ORDER BY product_id OFFSET 3 ROWS);
        DECLARE @p_lids  int = (SELECT TOP 1 product_id FROM zava.RefProduct ORDER BY product_id OFFSET 4 ROWS);

        -- Cup + Lid
        MERGE zava.MenuItemRecipe AS tgt
        USING (
          SELECT mi.menu_item_id, @p_cups AS product_id, CAST(1.0 AS decimal(12,3)) AS qty
          FROM zava.MenuItem mi WHERE mi.category = 'Beverage'
          UNION ALL
          SELECT mi.menu_item_id, @p_lids, CAST(1.0 AS decimal(12,3))
          FROM zava.MenuItem mi WHERE mi.category = 'Beverage'
        ) AS src(menu_item_id, product_id, qty)
        ON 1=0
        WHEN NOT MATCHED THEN INSERT(menu_item_id, product_id, qty_per_unit) VALUES(src.menu_item_id, src.product_id, src.qty);

        -- Beans
        MERGE zava.MenuItemRecipe AS tgt
        USING (
          SELECT mi.menu_item_id,
                 @p_beans AS product_id,
                 CAST(CASE mi.item_code
                      WHEN 'ESP-S'  THEN 0.009
                      WHEN 'ESP-D'  THEN 0.018
                      WHEN 'AMER-M' THEN 0.009
                      WHEN 'LAT-S'  THEN 0.009
                      WHEN 'LAT-M'  THEN 0.012
                      WHEN 'CAP-M'  THEN 0.009
                      WHEN 'MOCH-M' THEN 0.009
                      WHEN 'CB-M'   THEN 0.015
                      WHEN 'ICELAT' THEN 0.012
                      ELSE 0.0 END AS decimal(12,3)) AS qty
          FROM zava.MenuItem mi
          WHERE mi.category = 'Beverage'
        ) AS src(menu_item_id, product_id, qty)
        ON 1=0
        WHEN NOT MATCHED THEN INSERT(menu_item_id, product_id, qty_per_unit) VALUES(src.menu_item_id, src.product_id, src.qty);

        -- Milk
        MERGE zava.MenuItemRecipe AS tgt
        USING (
          SELECT mi.menu_item_id,
                 @p_milk AS product_id,
                 CAST(CASE mi.item_code
                      WHEN 'LAT-S'  THEN 0.20
                      WHEN 'LAT-M'  THEN 0.26
                      WHEN 'CAP-M'  THEN 0.18
                      WHEN 'MOCH-M' THEN 0.22
                      WHEN 'ICELAT' THEN 0.24
                      WHEN 'COCO-H' THEN 0.20
                      ELSE 0.0 END AS decimal(12,3)) AS qty
          FROM zava.MenuItem mi WHERE mi.category = 'Beverage'
        ) AS src(menu_item_id, product_id, qty)
        ON 1=0
        WHEN NOT MATCHED THEN INSERT(menu_item_id, product_id, qty_per_unit) VALUES(src.menu_item_id, src.product_id, src.qty);

        -- Syrup (Mocha only)
        MERGE zava.MenuItemRecipe AS tgt
        USING (
          SELECT mi.menu_item_id, @p_syr AS product_id, CAST(0.03 AS decimal(12,3)) AS qty
          FROM zava.MenuItem mi WHERE mi.item_code = 'MOCH-M'
        ) AS src(menu_item_id, product_id, qty)
        ON 1=0
        WHEN NOT MATCHED THEN INSERT(menu_item_id, product_id, qty_per_unit) VALUES(src.menu_item_id, src.product_id, src.qty);

        /* Customers — top-up to @MinCustomers */
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.Customer') AND type='U')
            CREATE TABLE zava.Customer (
              customer_id BIGINT IDENTITY(1,1) PRIMARY KEY,
              customer_number NVARCHAR(30) NOT NULL UNIQUE
                   CONSTRAINT DF_Customer_Number DEFAULT ('C-' + RIGHT(REPLICATE('0',6)+CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS NVARCHAR(20)),6)),
              first_name NVARCHAR(80) NULL,
              last_name NVARCHAR(80) NULL,
              email NVARCHAR(200) NULL,
              phone NVARCHAR(40) NULL,
              marketing_opt_in BIT NOT NULL DEFAULT(0),
              created_utc DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
            );

        DECLARE @have int = (SELECT COUNT(*) FROM zava.Customer);
        IF @have < @MinCustomers
        BEGIN
            INSERT zava.Customer(first_name, last_name, email, phone, marketing_opt_in)
            SELECT CONCAT(N'Cust', v.n), CONCAT(N'Last', v.n),
                   CONCAT('cust', v.n, '@example.com'),
                   CONCAT('+1-555-', RIGHT('0000'+CAST(v.n AS varchar(4)), 4)),
                   CASE WHEN (v.n % 3)=0 THEN 1 ELSE 0 END
            FROM (
              -- Generate rows up to (@MinCustomers - @have)
              SELECT TOP (@MinCustomers - @have) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
              FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) a(n)      -- 10
              CROSS JOIN (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) b(n) -- 100
              CROSS JOIN (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) c(n) -- 1,000
              CROSS JOIN (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) d(n) -- 10,000
            ) v;
        END
    END /* AutoSeedReferences */

    /* ======================================================================
       B) Build the day/store plan for orders
       ====================================================================== */
    IF OBJECT_ID('tempdb..#Days') IS NOT NULL DROP TABLE #Days;
    CREATE TABLE #Days(d date NOT NULL PRIMARY KEY);

    ;WITH dd AS (
      SELECT @StartDate AS d
      UNION ALL SELECT DATEADD(DAY,1,d) FROM dd WHERE d < @EndDate
    )
    INSERT #Days(d) SELECT d FROM dd OPTION (MAXRECURSION 0);

    IF OBJECT_ID('tempdb..#Plan') IS NOT NULL DROP TABLE #Plan;
    CREATE TABLE #Plan (store_id int NOT NULL, d date NOT NULL, order_seq int NOT NULL);

    INSERT #Plan(store_id, d, order_seq)
    SELECT rs.store_id, dy.d,
           v.n
    FROM zava.RefStore rs
    CROSS JOIN #Days dy
    CROSS APPLY (
      SELECT TOP (@OrdersPerStorePerDay) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) a(n)      -- 10
      CROSS JOIN (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) b(n) -- 100
      CROSS JOIN (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) c(n) -- 1,000
      CROSS JOIN (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) d(n) -- 10,000 (enough for most seeds)
    ) v;

    /* Device per store (choose one POS & one KIOSK deterministically) */
    IF OBJECT_ID('tempdb..#DevicePerStore') IS NOT NULL DROP TABLE #DevicePerStore;
    CREATE TABLE #DevicePerStore (store_id int PRIMARY KEY, device_id_pos int, device_id_kiosk int);

    INSERT #DevicePerStore(store_id, device_id_pos, device_id_kiosk)
    SELECT rs.store_id,
           (SELECT TOP 1 d.device_id FROM zava.Device d WHERE d.device_type='POS'   ORDER BY ABS(CHECKSUM(rs.store_id, d.device_id))) AS pos_id,
           (SELECT TOP 1 d.device_id FROM zava.Device d WHERE d.device_type='KIOSK' ORDER BY ABS(CHECKSUM(rs.store_id, d.device_id))) AS kiosk_id
    FROM zava.RefStore rs;

    /* ======================================================================
       C) Insert SalesOrder
       ====================================================================== */
    IF OBJECT_ID('tempdb..#NewOrders') IS NOT NULL DROP TABLE #NewOrders;
    CREATE TABLE #NewOrders (order_id bigint PRIMARY KEY, store_id int, d date);

    ;WITH o AS (
      SELECT p.store_id, p.d,
             CASE WHEN (ABS(CHECKSUM(p.store_id, p.d, p.order_seq)) % 100) < @PctKiosk THEN 'KIOSK' ELSE 'POS' END AS channel,
             (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 7))  % 24) AS hr,
             (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 11)) % 60) AS mi,
             (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 13)) % 60) AS ss,
             CASE WHEN (ABS(CHECKSUM(p.store_id, p.d, p.order_seq, 17)) % 100) < @PctCustomerAttached THEN 1 ELSE 0 END AS has_customer
      FROM #Plan p
    )
    INSERT zava.SalesOrder (store_id, device_id, staff_id, customer_id, channel, fulfillment_type,
                            status, created_utc, submitted_utc, completed_utc, pickup_name, notes)
    OUTPUT INSERTED.order_id, INSERTED.store_id, CAST(INSERTED.created_utc AS date) INTO #NewOrders(order_id, store_id, d)
    SELECT o.store_id,
           CASE o.channel WHEN 'KIOSK' THEN dps.device_id_kiosk ELSE dps.device_id_pos END,
           (SELECT TOP 1 s.staff_id FROM zava.Staff s ORDER BY ABS(CHECKSUM(o.store_id, s.staff_id))),
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

    /* ======================================================================
       D) Lines & taxes
       ====================================================================== */
    DECLARE @pl_any int = (SELECT TOP 1 price_list_id FROM zava.PriceList WHERE channel IN ('ANY','POS','KIOSK') ORDER BY priority, effective_from DESC);

    IF OBJECT_ID('tempdb..#OrderLinesPlan') IS NOT NULL DROP TABLE #OrderLinesPlan;
    CREATE TABLE #OrderLinesPlan(order_id bigint, line_no int);

    INSERT #OrderLinesPlan(order_id, line_no)
    SELECT no.order_id, x.n
    FROM #NewOrders no
    CROSS APPLY (
      SELECT TOP (1 + (ABS(CHECKSUM(no.order_id)) % @MaxLinesPerOrder))
             ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM (VALUES(1),(1),(1),(1),(1)) q(n) -- up to 5 lines easily; MaxLinesPerOrder guards it
    ) x;

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
                  WHERE so.order_id = pm.order_id
                    AND tr.tax_category_id = pm.tax_category_id
                  ORDER BY tr.effective_from DESC
                ), 0.0) AS decimal(12,2)) AS tax_amount_eur
    FROM #PickMenu pm;

    INSERT zava.SalesOrderLine(order_id, line_no, menu_item_id, qty, unit_price_eur, tax_amount_eur, notes)
    SELECT lwt.order_id, lwt.line_no, lwt.menu_item_id, lwt.qty, lwt.unit_price_eur, lwt.tax_amount_eur, NULL
    FROM #LineWithTax lwt;

    /* ======================================================================
       E) Totals & payment
       ====================================================================== */
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

    INSERT zava.Payment(order_id, tender_type_code, status, amount_eur, tip_amount_eur, provider, created_utc, card_brand, card_last4)
    SELECT no.order_id,
           CHOOSE(1 + (ABS(CHECKSUM(no.order_id, 1)) % 100),
                  'CARD','CARD','CARD','CARD','CARD','CARD','CARD',
                  'CASH','CASH','CASH','CASH','CASH',
                  'GIFTCARD') AS tender,
           'CAPTURED',
           CAST(so.subtotal_eur + so.tax_eur AS decimal(14,2)),
           CAST(ROUND((CASE WHEN so.channel='KIOSK' THEN 0.05 + (ABS(CHECKSUM(no.order_id, 9)) % 16)/100.0
                            ELSE (ABS(CHECKSUM(no.order_id, 9)) % 11)/100.0 END) * ISNULL(so.subtotal_eur,0), 2) AS decimal(14,2)) AS tip,
           CASE WHEN (ABS(CHECKSUM(no.order_id, 23)) % 100) < 70 THEN 'Adyen' ELSE 'Stripe' END,
           DATEADD(MINUTE, 9, so.created_utc),
           CHOOSE(1 + (ABS(CHECKSUM(no.order_id, 5)) % 4), 'VISA','MC','AMEX','DISC'),
           RIGHT('0000'+CAST(ABS(CHECKSUM(no.order_id, 6)) % 9999 AS varchar(4)),4)
    FROM #NewOrders no
    JOIN zava.SalesOrder so ON so.order_id = no.order_id;

    -- Final total includes tip
    UPDATE so
       SET tip_eur   = p.tip_amount_eur,
           total_eur = so.subtotal_eur + so.tax_eur + p.tip_amount_eur
    FROM zava.SalesOrder so
    JOIN zava.Payment p ON p.order_id = so.order_id
    WHERE so.order_id IN (SELECT order_id FROM #NewOrders);

    /* ======================================================================
       F) Optional: Post to Inventory & Outbox
       ====================================================================== */
    IF (@DoPostInventoryAndOutbox = 1)
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('zava.usp_PostSalesOrderToInventoryAndOutbox') AND type IN ('P','PC'))
        BEGIN
            RAISERROR('Posting proc [zava].[usp_PostSalesOrderToInventoryAndOutbox] not found. Set @DoPostInventoryAndOutbox = 0 or create the proc.', 16, 1);
        END
        ELSE
        BEGIN
            DECLARE @min_id bigint = (SELECT MIN(order_id) FROM #NewOrders);
            DECLARE @max_id bigint = (SELECT MAX(order_id) FROM #NewOrders);
            WHILE @min_id IS NOT NULL AND @min_id <= @max_id
            BEGIN
                BEGIN TRY
                    EXEC zava.usp_PostSalesOrderToInventoryAndOutbox @order_id = @min_id;
                END TRY
                BEGIN CATCH
                    -- swallow and continue; consider logging to a table if needed
                END CATCH
                SET @min_id += 1;
            END
        END
    END

    /* ======================================================================
       G) Summary
       ====================================================================== */
    DECLARE @orders int = (SELECT COUNT(*) FROM #NewOrders);
    DECLARE @lines  int = (SELECT COUNT(*) FROM zava.SalesOrderLine sol JOIN #NewOrders no ON no.order_id = sol.order_id);
    DECLARE @pmts   int = (SELECT COUNT(*) FROM zava.Payment p JOIN #NewOrders no ON no.order_id = p.order_id);

    PRINT CONCAT('Seed batch [', @SeedBatchTag, '] completed: ',
                 @orders, ' orders, ', @lines, ' lines, ', @pmts, ' payments.');

END
GO
