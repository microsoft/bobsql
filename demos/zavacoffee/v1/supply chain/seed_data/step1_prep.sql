SET NOCOUNT ON;
GO

/* ============================================================
   Global parameters (tune these to control total data volume)
   ============================================================ */

DECLARE @StoreCount               int = 50;     -- 50 coffee shops
DECLARE @SupplierCount            int = 28;     -- # suppliers across categories
DECLARE @ProductCount             int = 1200;   -- unique SKUs (beans/dairy/bakery/syrups/packaging)
DECLARE @DaysHistory              int = 540;    -- ~18 months of ops
DECLARE @StartDate                date = DATEADD(DAY, -@DaysHistory, CAST(SYSDATETIME() AS date));
DECLARE @EndDate                  date = DATEADD(DAY, -1, CAST(SYSDATETIME() AS date));

-- Purchase Orders / Shipments / Deliveries
DECLARE @POsPerStorePerWeek       int = 6;      -- each store orders ~6 POs/week across suppliers
DECLARE @POLinesPerPO_Min         int = 8;
DECLARE @POLinesPerPO_Max         int = 22;

-- Transactions scaling (this drives DB size)
DECLARE @AvgSalesLinesPerStorePerDay int = 14000; /* ~one every ~6 sec over 24h; tune upward to grow size */
DECLARE @ReceiptLinesFromDeliveries   int = 1;    -- generate RECEIPT InventoryTransaction from deliveries

-- ProofOfDelivery payload size (bytes) to grow size without massive row counts (optional)
DECLARE @PoDBytesPerDeliveryMin int = 12000;  -- 12 KB
DECLARE @PoDBytesPerDeliveryMax int = 48000;  -- 48 KB
/* Tip: Increase PoD ranges to grow DB size faster without extreme row counts */

/* ============================================================
   Utility: pseudo-random helpers and a numbers source
   ============================================================ */

IF OBJECT_ID('zava._util_RandBetween') IS NOT NULL DROP FUNCTION zava._util_RandBetween;
GO
CREATE FUNCTION zava._util_RandBetween(@seed int, @min int, @max int)
RETURNS int
AS
BEGIN
    -- deterministic-ish random based on a seed
    DECLARE @val float = ABS(CHECKSUM(@seed)) / 2147483647.0;
    RETURN @min + CAST(@val * (@max - @min + 1) AS int);
END;
GO

-- Lightweight inline Numbers (up to requested TOP) using powers-of-10 cross join
IF OBJECT_ID('zava._util_GetNumbers') IS NOT NULL DROP FUNCTION zava._util_GetNumbers;
GO
CREATE FUNCTION zava._util_GetNumbers(@top int)
RETURNS TABLE WITH SCHEMABINDING
AS RETURN
WITH
E1 AS (SELECT 1 AS c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),              -- 10
E2 AS (SELECT 1 AS c FROM E1 a CROSS JOIN E1 b),                                                -- 100
E4 AS (SELECT 1 AS c FROM E2 a CROSS JOIN E2 b),                                                -- 10,000
E8 AS (SELECT 1 AS c FROM E4 a CROSS JOIN E4 b),                                                -- 100,000,000
Nums AS (SELECT TOP (@top) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM E8)
SELECT n FROM Nums;
