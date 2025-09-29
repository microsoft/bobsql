CREATE OR ALTER PROCEDURE edge.kiosk_remove_item
    @session_id UNIQUEIDENTIFIER,
    @line_no    INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM edge.kiosk_session WHERE session_id = @session_id AND status = 'ACTIVE')
        THROW 51030, 'Session not found or not ACTIVE.', 1;

    DELETE FROM edge.kiosk_basket_item 
    WHERE session_id = @session_id AND line_no = @line_no;

    IF @@ROWCOUNT = 0
        THROW 51031, 'Basket line not found.', 1;

    INSERT INTO edge.kiosk_event (session_id, event_type, payload_json)
    VALUES (@session_id, 'REMOVE_FROM_CART', CONCAT(N'{"line_no":', @line_no, '}'));

    SELECT kbi.line_no, p.product_sku, p.product_name, kbi.quantity, kbi.unit_price, kbi.discount_amt, kbi.line_amount
    FROM edge.kiosk_basket_item kbi
    JOIN edge.product p ON p.product_id = kbi.product_id
    WHERE kbi.session_id = @session_id
    ORDER BY kbi.line_no;
END
GO