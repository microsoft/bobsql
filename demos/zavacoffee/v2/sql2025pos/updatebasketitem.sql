CREATE OR ALTER PROCEDURE edge.kiosk_update_item
    @session_id     UNIQUEIDENTIFIER,
    @line_no        INT,
    @new_quantity   DECIMAL(18,3),
    @unit_price_override DECIMAL(19,4) = NULL,
    @discount_amt   DECIMAL(19,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @new_quantity <= 0 THROW 51020, 'new_quantity must be > 0', 1;

    IF NOT EXISTS (SELECT 1 FROM edge.kiosk_session WHERE session_id = @session_id AND status = 'ACTIVE')
        THROW 51021, 'Session not found or not ACTIVE.', 1;

    UPDATE edge.kiosk_basket_item
       SET quantity = @new_quantity,
           unit_price = COALESCE(@unit_price_override, unit_price),
           discount_amt = COALESCE(@discount_amt, discount_amt)
     WHERE session_id = @session_id AND line_no = @line_no;

    IF @@ROWCOUNT = 0
        THROW 51022, 'Basket line not found.', 1;

    INSERT INTO edge.kiosk_event (session_id, event_type, payload_json)
    VALUES (@session_id, 'CART_UPDATED', 
            CONCAT(N'{"line_no":', @line_no, ',"qty":', FORMAT(@new_quantity, 'G', 'en-US'), '}'));

    SELECT kbi.line_no, p.product_sku, p.product_name, kbi.quantity, kbi.unit_price, kbi.discount_amt, kbi.line_amount
    FROM edge.kiosk_basket_item kbi
    JOIN edge.product p ON p.product_id = kbi.product_id
    WHERE kbi.session_id = @session_id
    ORDER BY kbi.line_no;
END
GO