CREATE OR ALTER PROCEDURE edge.kiosk_calculate_totals
    @session_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM edge.kiosk_session WHERE session_id = @session_id)
        THROW 51040, 'Session not found.', 1;

    ;WITH lines AS (
      SELECT kbi.product_id, kbi.quantity, kbi.unit_price, kbi.discount_amt,
             ROUND(kbi.quantity * kbi.unit_price - kbi.discount_amt, 4) AS line_amount
      FROM edge.kiosk_basket_item kbi
      WHERE kbi.session_id = @session_id
    )
    SELECT 
      CAST(SUM(l.line_amount) AS DECIMAL(19,4)) AS subtotal_amount,
      CAST(SUM(ROUND(l.line_amount * p.tax_rate, 4)) AS DECIMAL(19,4)) AS tax_amount,
      CAST(ROUND(SUM(l.line_amount) + SUM(ROUND(l.line_amount * p.tax_rate, 4)), 4) AS DECIMAL(19,4)) AS total_amount
    FROM lines l
    JOIN edge.product p ON p.product_id = l.product_id;
END
GO