SET NOCOUNT ON;
GO

/* ============================================================
   A) PARAMETERS — tune to your needs
   ============================================================ */
DECLARE @DaysBack                    int  = 21;    -- generate last N days (not including today)
DECLARE @OrdersPerStorePerDay        int  = 450;   -- volume driver; adjust per hardware/time
DECLARE @MaxLinesPerOrder            int  = 3;     -- 1..N lines per order
DECLARE @PctKiosk                    int  = 35;    -- % of orders taken on KIOSK vs POS
DECLARE @PctCustomerAttached         int  = 40;    -- % of orders with a known customer
DECLARE @DoPostInventoryAndOutbox    bit  = 0;     -- 1 = call zava.usp_PostSalesOrderToInventoryAndOutbox
DECLARE @SeedBatchTag                nvarchar(40) = CONCAT('POSSEED_', CONVERT(char(8), GETDATE(), 112)); -- used in order notes

-- Date window (inclusive)
DECLARE @StartDate date = DATEADD(DAY, -@DaysBack, CAST(SYSDATETIME() AS date));
DECLARE @EndDate   date = DATEADD(DAY, -1, CAST(SYSDATETIME() AS date));

/* ============================================================
   Utility tally function (numbers)
   ============================================================ */
IF OBJECT_ID('zava._util_GetNumbers') IS NOT NULL DROP FUNCTION zava._util_GetNumbers;
GO
CREATE FUNCTION zava._util_GetNumbers(@top int)
RETURNS TABLE WITH SCHEMABINDING
AS RETURN
WITH
E1 AS (SELECT 1 AS c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),     -- 10
E2 AS (SELECT 1 AS c FROM E1 a CROSS JOIN E1 b),                                       -- 100
E4 AS (SELECT 1 AS c FROM E2 a CROSS JOIN E2 b),                                       -- 10,000
E8 AS (SELECT 1 AS c FROM E4 a CROSS JOIN E4 b),                                       -- 100,000,000
Nums AS (SELECT TOP (@top) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM E8)
SELECT n FROM Nums;
GO