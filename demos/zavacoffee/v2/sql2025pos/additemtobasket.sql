CREATE OR ALTER PROCEDURE edge.kiosk_add_item
    @quantity     DECIMAL(18,3) = 1.0,
    @unit_price_override DECIMAL(19,4) = NULL,  -- optional override; if NULL use list_price
    @discount_amt DECIMAL(19,4) = 0.0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @quantity <= 0 THROW 51010, 'Quantity must be > 0', 1;

    DECLARE @store_id INT;

    SELECT @store_id = s.store_id
    FROM edge.kiosk_session ks
    JOIN edge.store s ON s.store_id = ks.store_id
    WHERE ks.session_id = @session_id AND ks.status = 'ACTIVE';

    IF @store_id IS NULL
        THROW 51011, 'Session not found or not ACTIVE.', 1;

    DECLARE @product_id BIGINT, @list_price DECIMAL(19,4), @is_active BIT;

    SELECT @product_id = p.product_id, @list_price = p.list_price, @is_active = p.is_active
    FROM edge.product p
    WHERE p.product_sku = @product_sku;

    IF @product_id IS NULL OR @is_active = 0
        THROW 51012, 'Invalid product or product inactive.', 1;

    DECLARE @unit_price DECIMAL(19,4) = COALESCE(@unit_price_override, @list_price);

    -- Next line number
    DECLARE @next_line INT = ISNULL(
        (SELECT MAX(line_no) FROM edge.kiosk_basket_item WHERE session_id = @session_id), 0
    ) + 1;

    INSERT INTO edge.kiosk_basket_item (session_id, line_no, product_id, quantity, unit_price, discount_amt)
    VALUES (@session_id, @next_line, @product_id, @quantity, @unit_price, @discount_amt);

    -- Telemetry
    INSERT INTO edge.kiosk_event (session_id, event_type, payload_json)
    VALUES (@session_id, 'ADD_TO_CART', 
            CONCAT(N'{"product_sku":"', @product_sku, '","qty":', FORMAT(@quantity, 'G', 'en-US'), '}'));

    -- Return current basket
    SELECT kbi.line_no, p.product_sku, p.product_name, kbi.quantity, kbi.unit_price, kbi.discount_amt, kbi.line_amount
    FROM edge.kiosk_basket_item kbi
    JOIN edge.product p ON p.product_id = kbi.product_id
    WHERE kbi.session_id = @session_id
    ORDER BY kbi.line_no;
END
GO    @session_id   UNIQUEIDENTIFIER,
    @product_sku  VARCHAR(64),
