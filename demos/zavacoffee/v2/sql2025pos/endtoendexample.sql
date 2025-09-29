-- 1) Start a session on kiosk KSK-01 in DAL01
DECLARE @session_id UNIQUEIDENTIFIER;
EXEC edge.kiosk_session_start 
     @store_code='DAL01', 
     @terminal_code='KSK-01', 
     @customer_id=NULL, 
     @session_id=@session_id OUTPUT;

-- 2) Add items
EXEC edge.kiosk_add_item @session_id=@session_id, @product_sku='CS-RUN-001', @quantity=1.0;
EXEC edge.kiosk_add_item @session_id=@session_id, @product_sku='CS-TRL-001', @quantity=2.0;

-- 3) Check totals
EXEC edge.kiosk_calculate_totals @session_id=@session_id;

-- 4) Checkout (idempotent with provided @pos_txn_id)
DECLARE @pos_txn_id UNIQUEIDENTIFIER = NEWSEQUENTIALID();
EXEC edge.kiosk_checkout_prod 
     @session_id=@session_id, 
     @payment_method='CARD', 
     @pos_txn_id=@pos_txn_id OUTPUT;

-- 5) Verify outbox
SELECT TOP 1 * FROM edge.outbox_event ORDER BY created_at_utc DESC;
