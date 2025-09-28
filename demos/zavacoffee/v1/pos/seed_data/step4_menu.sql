/* ============================================================
   D) MENU & PRICING (idempotent)
   ============================================================ */

-- If menu already exists, skip the whole block
IF NOT EXISTS (SELECT 1 FROM zava.MenuItem)
BEGIN
    DECLARE @tc_bev int = (SELECT tax_category_id FROM zava.TaxCategory WHERE code='BEVERAGE');
    DECLARE @tc_food int = (SELECT tax_category_id FROM zava.TaxCategory WHERE code='FOOD');
    DECLARE @tc_merch int = (SELECT tax_category_id FROM zava.TaxCategory WHERE code='MERCH');

    -- Pick 5 arbitrary product_ids to represent: beans, milk, syrup, cups, lids
    ;WITH rp AS (
        SELECT product_id,
               ROW_NUMBER() OVER (ORDER BY product_id) AS rn
        FROM zava.RefProduct
    )
    SELECT * INTO #recipe_products FROM (
        SELECT (SELECT product_id FROM rp WHERE rn=1) AS p_beans,
               (SELECT product_id FROM rp WHERE rn=2) AS p_milk,
               (SELECT product_id FROM rp WHERE rn=3) AS p_syrup,
               (SELECT product_id FROM rp WHERE rn=4) AS p_cups,
               (SELECT product_id FROM rp WHERE rn=5) AS p_lids
    ) s;

    /* Menu items */
    INSERT zava.MenuItem(item_code, item_name, category, product_id, tax_category_id, active)
    VALUES
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

    ('CROI',   N'Butter Croissant',       'Bakery',  NULL, @tc_food, 1),
    ('MUFF',   N'Blueberry Muffin',       'Bakery',  NULL, @tc_food, 1),
    ('BAGL',   N'Bagel',                  'Bakery',  NULL, @tc_food, 1),

    ('WATER',  N'Bottled Water',          'Merch',   NULL, @tc_merch,1),
    ('BEAN250',N'House Beans 250g',       'Merch',   NULL, @tc_merch,1),
    ('MUG',    N'Zava Ceramic Mug',       'Merch',   NULL, @tc_merch,1);

    -- Price list (global, ANY channel)
    INSERT zava.PriceList(list_name, store_id, channel, priority, effective_from, effective_to)
    VALUES (N'Global List', NULL, 'ANY', 10, DATEADD(DAY, -365, CAST(SYSDATETIME() AS date)), NULL);

    DECLARE @pl_id int = SCOPE_IDENTITY();

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
             WHEN 'BEAN250'T THEN 9.90
             WHEN 'MUG'    THEN 12.00
             ELSE 3.00 END,
           0
    FROM zava.MenuItem mi;

    /* Minimal “recipes” for beverages (just so posting can compute consumption)
       Uses the 5 placeholder products picked above. Quantities are illustrative. */
    DECLARE @p_beans int = (SELECT p_beans FROM #recipe_products);
    DECLARE @p_milk  int = (SELECT p_milk  FROM #recipe_products);
    DECLARE @p_syr   int = (SELECT p_syrup FROM #recipe_products);
    DECLARE @p_cups  int = (SELECT p_cups  FROM #recipe_products);
    DECLARE @p_lids  int = (SELECT p_lids  FROM #recipe_products);

    -- Base cup & lid for any beverage
    INSERT zava.MenuItemRecipe(menu_item_id, product_id, qty_per_unit)
    SELECT mi.menu_item_id, @p_cups, 1.0
    FROM zava.MenuItem mi
    WHERE mi.category = 'Beverage';

    INSERT zava.MenuItemRecipe(menu_item_id, product_id, qty_per_unit)
    SELECT mi.menu_item_id, @p_lids, 1.0
    FROM zava.MenuItem mi
    WHERE mi.category = 'Beverage';

    -- Beans & milk mapping by drink type
    INSERT zava.MenuItemRecipe(menu_item_id, product_id, qty_per_unit)
    SELECT mi.menu_item_id, @p_beans,
           CASE mi.item_code
             WHEN 'ESP-S'  THEN 0.009  -- 9g
             WHEN 'ESP-D'  THEN 0.018
             WHEN 'AMER-M' THEN 0.009
             WHEN 'LAT-S'  THEN 0.009
             WHEN 'LAT-M'  THEN 0.012
             WHEN 'CAP-M'  THEN 0.009
             WHEN 'MOCH-M' THEN 0.009
             WHEN 'CB-M'   THEN 0.015
             WHEN 'ICELAT' THEN 0.012
             WHEN 'TEA-H'  THEN 0.000
             WHEN 'COCO-H' THEN 0.000
             ELSE 0.0 END
    FROM zava.MenuItem mi
    WHERE mi.category = 'Beverage' AND mi.item_code NOT IN ('TEA-H','COCO-H');

    INSERT zava.MenuItemRecipe(menu_item_id, product_id, qty_per_unit)
    SELECT mi.menu_item_id, @p_milk,
           CASE mi.item_code
             WHEN 'LAT-S'  THEN 0.20
             WHEN 'LAT-M'  THEN 0.26
             WHEN 'CAP-M'  THEN 0.18
             WHEN 'MOCH-M' THEN 0.22
             WHEN 'ICELAT' THEN 0.24
             WHEN 'COCO-H' THEN 0.20
             ELSE 0.0 END
    FROM zava.MenuItem mi
    WHERE mi.category = 'Beverage';

    -- Syrup for Mocha only (as example)
    INSERT zava.MenuItemRecipe(menu_item_id, product_id, qty_per_unit)
    SELECT mi.menu_item_id, @p_syr, 0.03
    FROM zava.MenuItem mi
    WHERE mi.item_code = 'MOCH-M';

    DROP TABLE IF EXISTS #recipe_products;
END