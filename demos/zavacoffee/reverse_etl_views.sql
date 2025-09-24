/* 1a. Current stock per store/product */
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