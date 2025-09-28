SELECT rp.store_id, s.store_name, rp.product_id, p.product_name, rp.current_stock, rp.recommended_qty
FROM zava.ReplenishmentProposal rp
JOIN zava.Store s ON rp.store_id = s.store_id
JOIN zava.Product p ON rp.product_id = p.product_id
WHERE rp.recommended_qty > 0;