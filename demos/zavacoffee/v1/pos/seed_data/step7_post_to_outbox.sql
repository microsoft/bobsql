/* ============================================================
   G) OPTIONAL INVENTORY + OUTBOX POSTING
   ============================================================ */
IF (@DoPostInventoryAndOutbox = 1)
BEGIN
    DECLARE @min_id bigint = (SELECT MIN(order_id) FROM #NewOrders);
    DECLARE @max_id bigint = (SELECT MAX(order_id) FROM #NewOrders);

    WHILE @min_id IS NOT NULL AND @min_id <= @max_id
    BEGIN
        BEGIN TRY
            EXEC zava.usp_PostSalesOrderToInventoryAndOutbox @order_id = @min_id;
        END TRY
        BEGIN CATCH
            -- continue on error; log could be added
        END CATCH
        SET @min_id += 1;
    END
END
