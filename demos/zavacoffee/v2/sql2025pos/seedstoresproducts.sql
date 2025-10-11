USE [zavapos];
GO
/* ===========================================================
   Seed Data: Zava Coffee (North Richland Hills, Texas)
   Tables used: edge.store, edge.pos_terminal, edge.product, edge.inventory
   Assumptions:
     - edge.product has NO 'category' column (metadata is in product_attribute JSON)
     - product_attribute is of native JSON type
   Safety:
     - Products inserted in reserved product_id range [3,000,000 .. 3,009,999]
     - Re-runnable: deletes prior rows in that range and this store code
   =========================================================== */

SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRAN;

    /* ---------- Guardrails ---------- */
    IF OBJECT_ID('edge.store') IS NULL OR
       OBJECT_ID('edge.pos_terminal') IS NULL OR
       OBJECT_ID('edge.product') IS NULL OR
       OBJECT_ID('edge.inventory') IS NULL
    BEGIN
        RAISERROR('Required edge.* tables do not exist. Run your DDL first.', 16, 1);
        ROLLBACK TRAN;
        RETURN;
    END;

    /* ---------- Store (North Richland Hills, TX) ---------- */
    DECLARE @StoreCode  VARCHAR(16) = 'ZV-NRH-01';
    DECLARE @StoreName  NVARCHAR(200) = N'Zava Coffee – North Richland Hills';
    DECLARE @Street     NVARCHAR(200) = N'1234 Main St';
    DECLARE @City       NVARCHAR(100) = N'North Richland Hills';
    DECLARE @State      NCHAR(2)      = N'TX';
    DECLARE @Zip        NVARCHAR(10)  = N'76180';

    DECLARE @StoreId INT;

    IF EXISTS (SELECT 1 FROM edge.store WHERE store_code = @StoreCode)
    BEGIN
        SELECT @StoreId = store_id FROM edge.store WHERE store_code = @StoreCode;

        DELETE inv FROM edge.inventory AS inv WHERE inv.store_id = @StoreId;
        DELETE pt  FROM edge.pos_terminal pt WHERE pt.store_id = @StoreId;
        DELETE FROM edge.store WHERE store_id = @StoreId;
    END;

    INSERT INTO edge.store (store_code, store_name, StreetAddress, City, StateCode, ZipCode)
    VALUES (@StoreCode, @StoreName, @Street, @City, @State, @Zip);

    SET @StoreId = SCOPE_IDENTITY();

    /* ---------- POS terminals ---------- */
    INSERT INTO edge.pos_terminal (store_id, terminal_code, terminal_type, is_active)
    VALUES
        (@StoreId, 'REGISTER-01', 'REGISTER', 1),
        (@StoreId, 'REGISTER-02', 'REGISTER', 1),
        (@StoreId, 'KIOSK-01',    'KIOSK',    1);

    /* ---------- Clean prior seeded products (reserved range) ---------- */
    DECLARE @SeedBase INT = 3000000;   -- inclusive
    DECLARE @SeedMax  INT = 3099999;   -- inclusive (room for >1000 if needed)

    DELETE FROM edge.inventory
    WHERE product_id BETWEEN @SeedBase AND @SeedMax;

    DELETE FROM edge.product
    WHERE product_id BETWEEN @SeedBase AND @SeedMax;

    /* ---------- Build products (100+), beverage-heavy ---------- */
    IF OBJECT_ID('tempdb..#Products') IS NOT NULL DROP TABLE #Products;
    CREATE TABLE #Products
    (
        sku            VARCHAR(64)   NOT NULL PRIMARY KEY,
        name           NVARCHAR(300) NOT NULL,
        descr          NVARCHAR(2000)NOT NULL,
        attr_json      NVARCHAR(MAX) NOT NULL, -- will CAST to JSON on insert
        price          DECIMAL(19,4) NOT NULL,
        tax_rate       DECIMAL(9,4)  NOT NULL DEFAULT(0.0825),
        is_active      BIT           NOT NULL DEFAULT(1)
    );

    /* ---------- Helper in-memory sets ---------- */
    -- Sizes used commonly for beverages
    IF OBJECT_ID('tempdb..#Sizes_8_12_16') IS NOT NULL DROP TABLE #Sizes_8_12_16;
    CREATE TABLE #Sizes_8_12_16(size_oz INT, size_code VARCHAR(2));
    INSERT INTO #Sizes_8_12_16 VALUES (8,'08'),(12,'12'),(16,'16');

    IF OBJECT_ID('tempdb..#Sizes_12_16') IS NOT NULL DROP TABLE #Sizes_12_16;
    CREATE TABLE #Sizes_12_16(size_oz INT, size_code VARCHAR(2));
    INSERT INTO #Sizes_12_16 VALUES (12,'12'),(16,'16');

    IF OBJECT_ID('tempdb..#Sizes_3_4_5') IS NOT NULL DROP TABLE #Sizes_3_4_5;
    CREATE TABLE #Sizes_3_4_5(size_oz INT, size_code VARCHAR(2));
    INSERT INTO #Sizes_3_4_5 VALUES (3,'03'),(4,'04'),(5,'05');

    -- Classic flavors
    IF OBJECT_ID('tempdb..#Flavors') IS NOT NULL DROP TABLE #Flavors;
    CREATE TABLE #Flavors(flavor_code VARCHAR(8), flavor_name NVARCHAR(40));
    INSERT INTO #Flavors VALUES
        ('VAN','Vanilla'),
        ('CAR','Caramel'),
        ('HAZ','Hazelnut');

    -- Seasonal flavors
    IF OBJECT_ID('tempdb..#SeasonalFlavors') IS NOT NULL DROP TABLE #SeasonalFlavors;
    CREATE TABLE #SeasonalFlavors(flavor_code VARCHAR(8), flavor_name NVARCHAR(40));
    INSERT INTO #SeasonalFlavors VALUES
        ('PSP','Pumpkin Spice'),
        ('PEP','Peppermint');

    /* ---------- 1) Espresso & classics (about ~20) ---------- */
    -- Espresso single/double/ristretto
    INSERT INTO #Products(sku, name, descr, attr_json, price, tax_rate, is_active)
    VALUES
      ('BVRG-ESP-SGL', N'Espresso (Single)',
       N'Concentrated 1oz shot—syrupy and bold.',
       N'{"type":"beverage","subtype":"espresso","size_oz":1,"serve":"hot"}', 2.50, 0.0825, 1),
      ('BVRG-ESP-DBL', N'Espresso (Double)',
       N'Two shots pulled to a sweet, balanced profile.',
       N'{"type":"beverage","subtype":"espresso","size_oz":2,"serve":"hot"}', 3.25, 0.0825, 1),
      ('BVRG-RIST-SGL', N'Ristretto (Single)',
       N'Short pull for a dense, syrupy intensity.',
       N'{"type":"beverage","subtype":"ristretto","size_oz":1,"serve":"hot"}', 2.60, 0.0825, 1),
      ('BVRG-RIST-DBL', N'Ristretto (Double)',
       N'Short, concentrated double shot for rich flavor.',
       N'{"type":"beverage","subtype":"ristretto","size_oz":2,"serve":"hot"}', 3.35, 0.0825, 1);

    -- Cappuccino (12,16); Latte (12,16); Flat White (8,12); Cortado (4); Macchiato (3,5); Mocha (12,16); Americano (12,16)
    INSERT INTO #Products(sku,name,descr,attr_json,price,tax_rate,is_active)
    SELECT CONCAT('BVRG-CAP-',s.size_code),
           CONCAT(N'Cappuccino (',s.size_oz,N'oz)'),
           N'Equal parts espresso, steamed milk, and foam—light and aromatic.',
           CONCAT('{"type":"beverage","subtype":"cappuccino","size_oz":',s.size_oz,',"serve":"hot"}'),
           CASE s.size_oz WHEN 12 THEN 4.50 ELSE 4.95 END, 0.0825, 1
    FROM #Sizes_12_16 s
    UNION ALL
    SELECT CONCAT('BVRG-LAT-',s.size_code),
           CONCAT(N'Latte (',s.size_oz,N'oz)'),
           N'Two shots with steamed milk and silky microfoam.',
           CONCAT('{"type":"beverage","subtype":"latte","size_oz":',s.size_oz,',"serve":"hot","milk_default":"2%","alt_milks":["oat","almond","soy"]}'),
           CASE s.size_oz WHEN 12 THEN 4.75 ELSE 5.25 END, 0.0825, 1
    FROM #Sizes_12_16 s
    UNION ALL
    SELECT CONCAT('BVRG-FLW-',s.size_code),
           CONCAT(N'Flat White (',s.size_oz,N'oz)'),
           N'Rich espresso with thin microfoam for a velvety texture.',
           CONCAT('{"type":"beverage","subtype":"flat_white","size_oz":',s.size_oz,',"serve":"hot"}'),
           CASE s.size_oz WHEN 8 THEN 4.25 ELSE 4.75 END, 0.0825, 1
    FROM (SELECT 8 AS size_oz, '08' AS size_code UNION ALL SELECT 12,'12') s
    UNION ALL
    SELECT 'BVRG-CORT-04', N'Cortado (4oz)',
           N'Equal espresso and warm milk—balanced and smooth.',
           N'{"type":"beverage","subtype":"cortado","size_oz":4,"serve":"hot"}', 3.50, 0.0825, 1
    UNION ALL
    SELECT CONCAT('BVRG-MACH-',s.size_code),
           CONCAT(N'Macchiato (',s.size_oz,N'oz)'),
           N'Espresso marked with a dollop of foam.',
           CONCAT('{"type":"beverage","subtype":"macchiato","size_oz":',s.size_oz,',"serve":"hot"}'),
           CASE s.size_oz WHEN 3 THEN 2.85 ELSE 3.10 END, 0.0825, 1
    FROM #Sizes_3_4_5 s WHERE s.size_oz IN (3,5)
    UNION ALL
    SELECT CONCAT('BVRG-MOCH-',s.size_code),
           CONCAT(N'Mocha (',s.size_oz,N'oz)'),
           N'Espresso with steamed milk and dark chocolate sauce.',
           CONCAT('{"type":"beverage","subtype":"mocha","size_oz":',s.size_oz,',"serve":"hot","chocolate":"dark"}'),
           CASE s.size_oz WHEN 12 THEN 5.25 ELSE 5.75 END, 0.0825, 1
    FROM #Sizes_12_16 s
    UNION ALL
    SELECT CONCAT('BVRG-AMER-',s.size_code),
           CONCAT(N'Americano (',s.size_oz,N'oz)'),
           N'Espresso lengthened with hot water for a smooth, long cup.',
           CONCAT('{"type":"beverage","subtype":"americano","size_oz":',s.size_oz,',"serve":"hot"}'),
           CASE s.size_oz WHEN 12 THEN 3.35 ELSE 3.75 END, 0.0825, 1
    FROM #Sizes_12_16 s;

    /* ---------- 2) Flavored lattes (classic + seasonal) hot & iced (~30+) ---------- */
    -- Classics (vanilla/caramel/hazelnut) hot (LAT) and iced (ILAT) in 12/16
    INSERT INTO #Products(sku,name,descr,attr_json,price,tax_rate,is_active)
    SELECT CONCAT('BVRG-LAT-', f.flavor_code, '-', s.size_code) AS sku,
           CONCAT(f.flavor_name, N' Latte (', s.size_oz, N'oz)') AS name,
           CONCAT(N'Latte with ', LOWER(f.flavor_name), N' syrup; creamy and balanced.') AS descr,
           CONCAT('{"type":"beverage","subtype":"latte","size_oz":',s.size_oz,',"serve":"hot","flavor":"',f.flavor_name,'","alt_milks":["oat","almond","soy"]}') AS attr_json,
           CASE s.size_oz WHEN 12 THEN 5.05 ELSE 5.55 END AS price, 0.0825, 1
    FROM #Flavors f CROSS JOIN #Sizes_12_16 s
    UNION ALL
    SELECT CONCAT('BVRG-ILAT-', f.flavor_code, '-', s.size_code),
           CONCAT(N'Iced ', f.flavor_name, N' Latte (', s.size_oz, N'oz)'),
           CONCAT(N'Iced latte with ', LOWER(f.flavor_name), N' syrup; refreshing and smooth.'),
           CONCAT('{"type":"beverage","subtype":"latte","size_oz":',s.size_oz,',"serve":"cold","flavor":"',f.flavor_name,'","alt_milks":["oat","almond","soy"]}'),
           CASE s.size_oz WHEN 12 THEN 5.15 ELSE 5.65 END, 0.0825, 1
    FROM #Flavors f CROSS JOIN #Sizes_12_16 s;

    -- Seasonal: Pumpkin Spice & Peppermint (hot + iced, 12/16)
    INSERT INTO #Products(sku,name,descr,attr_json,price,tax_rate,is_active)
    SELECT CONCAT('BVRG-LAT-', f.flavor_code, '-', s.size_code),
           CONCAT(f.flavor_name, N' Latte (', s.size_oz, N'oz)'),
           CONCAT(f.flavor_name, N' spice notes in a creamy latte.'),
           CONCAT('{"type":"beverage","subtype":"latte","size_oz":',s.size_oz,',"serve":"hot","flavor":"',f.flavor_name,'"}'),
           CASE s.size_oz WHEN 12 THEN 5.45 ELSE 5.95 END, 0.0825, 1
    FROM #SeasonalFlavors f CROSS JOIN #Sizes_12_16 s
    UNION ALL
    SELECT CONCAT('BVRG-ILAT-', f.flavor_code, '-', s.size_code),
           CONCAT(N'Iced ', f.flavor_name, N' Latte (', s.size_oz, N'oz)'),
           CONCAT(N'Iced latte with ', f.flavor_name, N' notes; cool and festive.'),
           CONCAT('{"type":"beverage","subtype":"latte","size_oz":',s.size_oz,',"serve":"cold","flavor":"',f.flavor_name,'"}'),
           CASE s.size_oz WHEN 12 THEN 5.55 ELSE 6.05 END, 0.0825, 1
    FROM #SeasonalFlavors f CROSS JOIN #Sizes_12_16 s;

    /* ---------- 3) Brewed & cold coffee (~15) ---------- */
    -- Drip (12/16), Pour-over (12), Cold Brew (12/16), Nitro Cold Brew (12/16), Iced Americano/Mocha/Latte/Matcha/Chai
    INSERT INTO #Products(sku,name,descr,attr_json,price,tax_rate,is_active)
    SELECT CONCAT('BVRG-DRIP-',s.size_code),
           CONCAT(N'Drip Coffee (',s.size_oz,N'oz)'),
           N'Freshly brewed batch coffee; smooth and balanced.',
           CONCAT('{"type":"beverage","subtype":"drip","size_oz":',s.size_oz,',"serve":"hot"}'),
           CASE s.size_oz WHEN 12 THEN 2.65 ELSE 2.95 END, 0.0825, 1
    FROM #Sizes_12_16 s
    UNION ALL
    SELECT 'BVRG-POUR-12', N'Pour-Over (12oz)',
           N'Hand-brewed clarity with a clean finish.',
           N'{"type":"beverage","subtype":"pour_over","size_oz":12,"serve":"hot"}',
           3.95, 0.0825, 1
    UNION ALL
    SELECT CONCAT('BVRG-CBR-',s.size_code),
           CONCAT(N'Cold Brew (',s.size_oz,N'oz)'),
           N'12-hour steeped coffee—low acidity and smooth.',
           CONCAT('{"type":"beverage","subtype":"cold_brew","size_oz":',s.size_oz,',"serve":"cold"}'),
           CASE s.size_oz WHEN 12 THEN 3.95 ELSE 4.45 END, 0.0825, 1
    FROM #Sizes_12_16 s
    UNION ALL
    SELECT CONCAT('BVRG-NCBR-',s.size_code),
           CONCAT(N'Nitro Cold Brew (',s.size_oz,N'oz)'),
           N'Creamy nitrogen cascade with a naturally sweet finish.',
           CONCAT('{"type":"beverage","subtype":"nitro_cold_brew","size_oz":',s.size_oz,',"serve":"cold"}'),
           CASE s.size_oz WHEN 12 THEN 4.65 ELSE 5.15 END, 0.0825, 1
    FROM #Sizes_12_16 s
    UNION ALL
    SELECT 'BVRG-IAMER-16', N'Iced Americano (16oz)',
           N'Espresso over cold water—clean and bold.',
           N'{"type":"beverage","subtype":"americano","size_oz":16,"serve":"cold"}',
           3.85, 0.0825, 1
    UNION ALL
    SELECT 'BVRG-IMOCH-16', N'Iced Mocha (16oz)',
           N'Chilled mocha with dark chocolate.',
           N'{"type":"beverage","subtype":"mocha","size_oz":16,"serve":"cold"}',
           5.85, 0.0825, 1
    UNION ALL
    SELECT 'BVRG-ILAT-16', N'Iced Latte (16oz)',
           N'Espresso over ice with cold milk; refreshing.',
           N'{"type":"beverage","subtype":"latte","size_oz":16,"serve":"cold"}',
           5.25, 0.0825, 1
    UNION ALL
    SELECT 'BVRG-IMATCH-16', N'Iced Matcha Latte (16oz)',
           N'Whisked matcha with cold milk; vegetal and creamy.',
           N'{"type":"beverage","subtype":"matcha_latte","size_oz":16,"serve":"cold"}',
           5.65, 0.0825, 1
    UNION ALL
    SELECT 'BVRG-ICHAI-16', N'Iced Chai Latte (16oz)',
           N'Spiced black tea concentrate with cold milk.',
           N'{"type":"beverage","subtype":"chai_latte","size_oz":16,"serve":"cold"}',
           5.65, 0.0825, 1;

    /* ---------- 4) Non-coffee hot & teas (~10) ---------- */
    INSERT INTO #Products(sku,name,descr,attr_json,price,tax_rate,is_active)
    VALUES
      ('BVRG-HOTCH-12', N'Hot Chocolate (12oz)',
       N'Deep cocoa comfort with steamed milk.',
       N'{"type":"beverage","subtype":"hot_chocolate","size_oz":12,"serve":"hot"}', 3.95, 0.0825, 1),
      ('BVRG-HOTCH-16', N'Hot Chocolate (16oz)',
       N'Richer cocoa in a larger cup.',
       N'{"type":"beverage","subtype":"hot_chocolate","size_oz":16,"serve":"hot"}', 4.45, 0.0825, 1),
      ('BVRG-TEA-EARL-12', N'Hot Tea – Earl Grey (12oz)',
       N'Black tea scented with bergamot.',
       N'{"type":"beverage","subtype":"hot_tea","variety":"earl_grey","size_oz":12,"serve":"hot"}', 2.85, 0.0825, 1),
      ('BVRG-TEA-PEPP-12', N'Hot Tea – Peppermint (12oz)',
       N'Caffeine-free herbal with cooling mint.',
       N'{"type":"beverage","subtype":"hot_tea","variety":"peppermint","size_oz":12,"serve":"hot"}', 2.85, 0.0825, 1),
      ('BVRG-TEA-CHAM-12', N'Hot Tea – Chamomile (12oz)',
       N'Calming floral herbal tea.',
       N'{"type":"beverage","subtype":"hot_tea","variety":"chamomile","size_oz":12,"serve":"hot"}', 2.85, 0.0825, 1),
      ('BVRG-TEA-JASM-12', N'Hot Tea – Jasmine Green (12oz)',
       N'Green tea scented with jasmine.',
       N'{"type":"beverage","subtype":"hot_tea","variety":"jasmine_green","size_oz":12,"serve":"hot"}', 2.95, 0.0825, 1),
      ('BVRG-CHAI-16', N'Chai Latte (16oz)',
       N'Spiced black tea with steamed milk.',
       N'{"type":"beverage","subtype":"chai_latte","size_oz":16,"serve":"hot"}', 5.50, 0.0825, 1),
      ('BVRG-MATCH-12', N'Matcha Latte (12oz)',
       N'Stone-ground green tea with milk—creamy and vegetal.',
       N'{"type":"beverage","subtype":"matcha_latte","size_oz":12,"serve":"hot"}', 5.25, 0.0825, 1),
      ('BVRG-ICEDTEA-16', N'Iced Black Tea – Lemon (16oz)',
       N'Lightly sweetened black tea with lemon.',
       N'{"type":"beverage","subtype":"iced_tea","size_oz":16,"serve":"cold"}', 3.25, 0.0825, 1);

    /* ---------- 5) Whole bean coffee (retail) (~20) ---------- */
    IF OBJECT_ID('tempdb..#Beans') IS NOT NULL DROP TABLE #Beans;
    CREATE TABLE #Beans(code VARCHAR(12), name NVARCHAR(100), origin NVARCHAR(100), roast NVARCHAR(30), bag_oz INT, price DECIMAL(10,2));
    INSERT INTO #Beans VALUES
      ('ETH-12',  N'Whole Bean – Ethiopia Yirgacheffe (12oz)',  N'Ethiopia Yirgacheffe', 'light', 12, 16.95),
      ('ETHN-12', N'Whole Bean – Ethiopia Natural (12oz)',     N'Ethiopia Natural',     'light', 12, 16.95),
      ('KEN-12',  N'Whole Bean – Kenya AA (12oz)',             N'Kenya AA',             'medium',12, 17.50),
      ('COL-12',  N'Whole Bean – Colombia Supremo (12oz)',     N'Colombia Supremo',     'medium',12, 15.95),
      ('BRA-12',  N'Whole Bean – Brazil Santos (12oz)',        N'Brazil Santos',        'medium',12, 14.95),
      ('GUA-12',  N'Whole Bean – Guatemala Antigua (12oz)',    N'Guatemala Antigua',    'medium',12, 16.25),
      ('SUM-12',  N'Whole Bean – Sumatra Mandheling (12oz)',   N'Sumatra Mandheling',   'dark',  12, 16.95),
      ('CR-12',   N'Whole Bean – Costa Rica Tarrazú (12oz)',   N'Costa Rica Tarrazú',   'medium',12, 16.50),
      ('RWA-12',  N'Whole Bean – Rwanda (12oz)',               N'Rwanda',               'light', 12, 16.50),
      ('HON-12',  N'Whole Bean – Honduras (12oz)',             N'Honduras',             'medium',12, 15.50),
      ('PER-12',  N'Whole Bean – Peru (12oz)',                 N'Peru',                 'medium',12, 15.50),
      ('ESP-32',  N'Whole Bean – House Espresso (2lb)',        N'Blend',                'medium',32, 29.50),
      ('DECAF-12',N'Whole Bean – Decaf Blend (12oz)',          N'Blend',                'medium',12, 15.50),
      ('SEAS-12', N'Whole Bean – Seasonal Blend (12oz)',       N'Blend',                'medium',12, 16.50),
      ('BFAST-12',N'Whole Bean – Breakfast Blend (12oz)',      N'Blend',                'light', 12, 14.95),
      ('FR-12',   N'Whole Bean – French Roast (12oz)',         N'Blend',                'dark',  12, 15.95),
      ('IT-12',   N'Whole Bean – Italian Roast (12oz)',        N'Blend',                'dark',  12, 15.95),
      ('HOL-12',  N'Whole Bean – Holiday Blend (12oz)',        N'Blend',                'medium',12, 16.95),
      ('PNG-12',  N'Whole Bean – Papua New Guinea (12oz)',     N'Papua New Guinea',     'medium',12, 16.50),
      ('MX-12',   N'Whole Bean – Mexico Chiapas (12oz)',       N'Mexico Chiapas',       'medium',12, 15.75);

    INSERT INTO #Products(sku, name, descr, attr_json, price, tax_rate, is_active)
    SELECT CONCAT('BEAN-', code) AS sku,
           name,
           CONCAT(N'Roasted whole beans (', roast, N'); ideal for home brewing.') AS descr,
           CONCAT('{"type":"retail","subtype":"whole_bean","origin":"',REPLACE(origin,'"','\"'),
                  '","roast":"',roast,'",',
                  CASE WHEN bag_oz=32 THEN '"bag_size_lb":2'
                       ELSE CONCAT('"bag_size_oz":',bag_oz)
                  END,
                  '}') AS attr_json,
           price, 0.0825, 1
    FROM #Beans;

    /* ---------- 6) Bakery & food (~20) ---------- */
    INSERT INTO #Products(sku,name,descr,attr_json,price,tax_rate,is_active)
    VALUES
      ('FOOD-CRSNT',  N'Butter Croissant',
       N'Flaky laminated pastry, baked fresh daily.',
       N'{"type":"food","subtype":"pastry"}', 3.65, 0.0825, 1),
      ('FOOD-CRSNT-CHOC', N'Chocolate Croissant',
       N'Butter croissant with dark chocolate baton.',
       N'{"type":"food","subtype":"pastry"}', 4.15, 0.0825, 1),
      ('FOOD-CRSNT-ALM', N'Almond Croissant',
       N'Buttery croissant filled with almond cream, topped with slices.',
       N'{"type":"food","subtype":"pastry"}', 4.35, 0.0825, 1),
      ('FOOD-MUF-BLU', N'Blueberry Muffin',
       N'Classic muffin with a crunchy sugar top.',
       N'{"type":"food","subtype":"muffin"}', 3.45, 0.0825, 1),
      ('FOOD-MUF-BAN', N'Banana Nut Muffin',
       N'Moist banana muffin with toasted walnuts.',
       N'{"type":"food","subtype":"muffin"}', 3.55, 0.0825, 1),
      ('FOOD-CIN-ROLL', N'Cinnamon Roll',
       N'Swirl of cinnamon sugar with a light glaze.',
       N'{"type":"food","subtype":"pastry"}', 3.95, 0.0825, 1),
      ('FOOD-BAG-PLN', N'Bagel – Plain',
       N'Boiled, baked, and ready to toast; cream cheese available.',
       N'{"type":"food","subtype":"bagel"}', 2.75, 0.0825, 1),
      ('FOOD-BAG-EVRY', N'Bagel – Everything',
       N'Savory blend of seeds and spices; toast on request.',
       N'{"type":"food","subtype":"bagel"}', 2.95, 0.0825, 1),
      ('FOOD-DAN-CHEE', N'Cheese Danish',
       N'Soft pastry with tangy cheese filling.',
       N'{"type":"food","subtype":"pastry"}', 3.85, 0.0825, 1),
      ('FOOD-CRSNT-HSW', N'Ham & Swiss Croissant',
       N'Buttery croissant with ham and Swiss cheese.',
       N'{"type":"food","subtype":"savory_pastry"}', 5.25, 0.0825, 1),
      ('FOOD-PAN-TUR', N'Turkey Pesto Panini',
       N'Turkey, mozzarella, tomato, and basil pesto—pressed warm.',
       N'{"type":"food","subtype":"panini"}', 6.95, 0.0825, 1),
      ('FOOD-SAND-BFST', N'Breakfast Sandwich',
       N'Egg, cheddar, and bacon on a toasted brioche bun.',
       N'{"type":"food","subtype":"breakfast_sandwich"}', 5.95, 0.0825, 1),
      ('FOOD-AVO-TOAST', N'Avocado Toast',
       N'Smashed avocado, lemon, chili flakes on sourdough.',
       N'{"type":"food","subtype":"toast"}', 6.25, 0.0825, 1),
      ('FOOD-OAT-CUP', N'Oatmeal Cup',
       N'Hearty oats with brown sugar and dried fruit.',
       N'{"type":"food","subtype":"oatmeal"}', 3.45, 0.0825, 1),
      ('FOOD-YOG-PAR', N'Yogurt Parfait',
       N'Creamy yogurt layered with granola and berries.',
       N'{"type":"food","subtype":"parfait"}', 4.15, 0.0825, 1),
      ('FOOD-CK-CHOC', N'Cookie – Chocolate Chip',
       N'Chewy cookie with semi-sweet chips.',
       N'{"type":"food","subtype":"cookie"}', 2.25, 0.0825, 1),
      ('FOOD-CK-OAT', N'Cookie – Oatmeal Raisin',
       N'Old-fashioned oats with plump raisins.',
       N'{"type":"food","subtype":"cookie"}', 2.25, 0.0825, 1),
      ('FOOD-CK-SNICK', N'Cookie – Snickerdoodle',
       N'Cinnamon-sugar coated classic.',
       N'{"type":"food","subtype":"cookie"}', 2.25, 0.0825, 1),
      ('FOOD-BRST-PLT', N'Breakfast Plate',
       N'Scrambled eggs, toast, and fruit.',
       N'{"type":"food","subtype":"plate"}', 6.95, 0.0825, 1),
      ('FOOD-GRAN-BAR', N'Granola Bar',
       N'Oats, honey, and nuts; great on the go.',
       N'{"type":"food","subtype":"snack"}', 1.95, 0.0825, 1);

    /* ---------- 7) Merch & retail beverages (~8) ---------- */
    INSERT INTO #Products(sku,name,descr,attr_json,price,tax_rate,is_active)
    VALUES
      ('MRCH-MUG-12',  N'Zava Ceramic Mug (12oz)',
       N'White ceramic mug with Zava branding.',
       N'{"type":"merch","subtype":"mug","size_oz":12,"color":"white"}', 12.00, 0.0825, 1),
      ('MRCH-TMB-16',  N'Cold Cup Tumbler (16oz)',
       N'Clear cold cup with reusable straw.',
       N'{"type":"merch","subtype":"tumbler","size_oz":16}', 14.00, 0.0825, 1),
      ('MRCH-INS-20',  N'Insulated Tumbler (20oz)',
       N'Keeps drinks hot or cold longer.',
       N'{"type":"merch","subtype":"tumbler","size_oz":20,"insulated":true}', 22.00, 0.0825, 1),
      ('MRCH-STR-SET', N'Reusable Straw Set',
       N'Stainless straws with cleaning brush.',
       N'{"type":"merch","subtype":"straw_set"}', 7.00, 0.0825, 1),
      ('RETL-WATER-16', N'Bottled Water (16oz)',
       N'Still water in recyclable bottle.',
       N'{"type":"retail","subtype":"bottled_water","size_oz":16}', 1.75, 0.0825, 1),
      ('RETL-SPARK-16', N'Sparkling Water (16oz)',
       N'Lightly carbonated mineral water.',
       N'{"type":"retail","subtype":"sparkling_water","size_oz":16}', 2.25, 0.0825, 1),
      ('MRCH-GC-25',   N'Gift Card – $25',
       N'Prepaid card redeemable at Zava Coffee.',
       N'{"type":"merch","subtype":"gift_card","value":25}', 25.00, 0.0000, 1),
      ('MRCH-GC-50',   N'Gift Card – $50',
       N'Prepaid card redeemable at Zava Coffee.',
       N'{"type":"merch","subtype":"gift_card","value":50}', 50.00, 0.0000, 1);

    /* ---------- Sanity check: ensure >= 100 products ---------- */
    DECLARE @Count INT = (SELECT COUNT(*) FROM #Products);
    IF @Count < 100
    BEGIN
        RAISERROR('Seed generated only %d products; expected >= 100.', 16, 1, @Count);
        ROLLBACK TRAN;
        RETURN;
    END;

    /* ---------- Insert into edge.product with reserved product_id range ---------- */
    ;WITH numbered AS
    (
        SELECT ROW_NUMBER() OVER (ORDER BY sku) AS rn, p.*
        FROM #Products p
    )
    INSERT INTO edge.product
        (product_id, product_sku, product_name, product_desc, product_attribute, list_price, tax_rate, is_active)
    SELECT @SeedBase + rn - 1,
           sku,
           name,
           descr,
           CAST(attr_json AS JSON),      -- cast to native JSON
           price,
           tax_rate,
           is_active
    FROM numbered
    ORDER BY rn;

    /* ---------- Inventory for this store (weighted) ---------- */
    -- More on-hand units for beverages; fewer for food/beans/merch
    INSERT INTO edge.inventory (store_id, product_id, on_hand_qty, last_updated_at)
    SELECT @StoreId,
           p.product_id,
           CASE 
               WHEN LEFT(p.product_sku,4) = 'BVRG' THEN 400
               WHEN LEFT(p.product_sku,4) = 'BEAN' THEN  40
               WHEN LEFT(p.product_sku,4) = 'FOOD' THEN  60
               WHEN LEFT(p.product_sku,4) = 'MRCH' THEN  24
               WHEN LEFT(p.product_sku,4) = 'RETL' THEN  96
               ELSE 50
           END,
           SYSUTCDATETIME()
    FROM edge.product p
    WHERE p.product_id BETWEEN @SeedBase AND @SeedMax;

    COMMIT TRAN;

    PRINT CONCAT('Seed complete: ', @Count, ' products for store ', @StoreCode, ' (ID=', @StoreId, ').');

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    DECLARE @msg NVARCHAR(4000) =
        CONCAT('Seed failed: ', ERROR_MESSAGE(), ' (', ERROR_NUMBER(), '/', ERROR_SEVERITY(), ') at line ', ERROR_LINE());
    RAISERROR(@msg, 16, 1);
END CATCH;
