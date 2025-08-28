------------------------------------------------------------
-- Current On-Hand per store/product (as of NOW)
------------------------------------------------------------
CREATE OR ALTER VIEW zava.v_CurrentInventory AS
SELECT it.store_id, it.product_id,
       SUM(it.qty) AS on_hand_qty
FROM zava.InventoryTransaction it
GROUP BY it.store_id, it.product_id;
GO

------------------------------------------------------------
-- Reorder candidates (below reorder point)
------------------------------------------------------------
CREATE OR ALTER VIEW zava.v_ReorderCandidates AS
SELECT s.store_code, p.sku,
       spp.store_id, spp.product_id,
       ci.on_hand_qty,
       spp.reorder_point, spp.reorder_qty, spp.max_stock,
       sp.supplier_id, sp.price_eur, sp.lead_time_days
FROM zava.StoreProductParam spp
JOIN zava.v_CurrentInventory ci ON ci.store_id = spp.store_id AND ci.product_id = spp.product_id
JOIN zava.Product p ON p.product_id = spp.product_id
JOIN zava.SupplierProduct sp ON sp.product_id = spp.product_id
JOIN zava.Store s ON s.store_id = spp.store_id
WHERE ci.on_hand_qty <= spp.reorder_point;
