-- Start a kiosk session on the first store's kiosk
DECLARE @sid UNIQUEIDENTIFIER = NEWSEQUENTIALID();

INSERT INTO edge.kiosk_session (session_id, store_id, terminal_id, customer_id, started_at_utc, status)
SELECT TOP 1 @sid, st.store_id, t.terminal_id, NULL, SYSUTCDATETIME(), 'ACTIVE'
FROM edge.store st
JOIN edge.pos_terminal t ON t.store_id = st.store_id AND t.terminal_type = 'KIOSK'
ORDER BY st.store_id;

-- Add a couple of items to the basket (pick two active, in-stock products)
;WITH pick AS (
  SELECT TOP 2 i.store_id, p.product_id, p.list_price
  FROM edge.kiosk_session s
  JOIN edge.inventory i ON i.store_id = s.store_id AND i.on_hand_qty > 0
  JOIN edge.product p   ON p.product_id = i.product_id AND p.is_active = 1
  WHERE s.session_id = @sid
  ORDER BY p.product_id
)
INSERT INTO edge.kiosk_basket_item (session_id, line_no, product_id, quantity, unit_price, discount_amt)
SELECT @sid, ROW_NUMBER() OVER (ORDER BY product_id), product_id, 1.0, list_price, 0.0
FROM pick;

-- Show basket + on-hand
SELECT kbi.session_id, kbi.line_no, p.product_sku, p.product_name, kbi.quantity, kbi.unit_price,
       i.on_hand_qty AS on_hand_now
FROM edge.kiosk_basket_item kbi
JOIN edge.product p   ON p.product_id = kbi.product_id
JOIN edge.kiosk_session s ON s.session_id = kbi.session_id
JOIN edge.inventory i ON i.store_id = s.store_id AND i.product_id = kbi.product_id
WHERE kbi.session_id = @sid
ORDER BY kbi.line_no;