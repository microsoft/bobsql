/* Ensure schema exists */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'zava')
    EXEC('CREATE SCHEMA zava');
GO

/* Optional: Ensure sequences exist */
IF OBJECT_ID('zava.seq_shipment_number', 'SO') IS NULL
    CREATE SEQUENCE zava.seq_shipment_number START WITH 1 INCREMENT BY 1;
GO
IF OBJECT_ID('zava.seq_delivery_number', 'SO') IS NULL
    CREATE SEQUENCE zava.seq_delivery_number START WITH 1 INCREMENT BY 1;
GO

/* Benchmark tables */
IF OBJECT_ID('zava.BenchmarkRun','U') IS NULL
CREATE TABLE zava.BenchmarkRun
(
    run_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    started_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    completed_utc DATETIME2(3) NULL,
    mix_json      NVARCHAR(2000) NULL,
    notes         NVARCHAR(400) NULL
);
GO

IF OBJECT_ID('zava.BenchmarkTxn','U') IS NULL
CREATE TABLE zava.BenchmarkTxn
(
    run_id        BIGINT NOT NULL,
    txn_name      NVARCHAR(40) NOT NULL,
    worker_id     INT NOT NULL,
    ops           BIGINT NOT NULL,
    avg_ms        FLOAT NOT NULL,
    p95_ms        FLOAT NULL,
    p99_ms        FLOAT NULL,
    started_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    completed_utc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_BenchmarkTxn PRIMARY KEY (run_id, txn_name, worker_id),
    CONSTRAINT FK_BenchmarkTxn_Run FOREIGN KEY (run_id) REFERENCES zava.BenchmarkRun(run_id)
);
GO

/* Skew helper: deterministic UDF (caller passes random @r in [0,1)) */
IF OBJECT_ID('zava.fn_pick_skewed_id','FN') IS NOT NULL
    DROP FUNCTION zava.fn_pick_skewed_id;
GO
CREATE FUNCTION zava.fn_pick_skewed_id
(
    @min_id INT,
    @max_id INT,
    @bias   FLOAT,   -- 0 = uniform; >0 increasingly skewed (e.g., 1.0..1.5)
    @r      FLOAT    -- caller-supplied random in [0,1)
)
RETURNS INT
AS
BEGIN
    DECLARE @range INT = @max_id - @min_id + 1;
    -- If bias = 0 => uniform
    DECLARE @p FLOAT =
        CASE WHEN @bias = 0 THEN @r
             ELSE POWER(@r, 1.0 / @bias)
        END;
    RETURN @min_id + CAST(FLOOR(@p * @range) AS INT);
END;
GO

/* Place Purchase Order */
IF OBJECT_ID('zava.usp_PlacePurchaseOrder','P') IS NOT NULL
    DROP PROCEDURE zava.usp_PlacePurchaseOrder;
GO
CREATE PROCEDURE zava.usp_PlacePurchaseOrder
    @store_id INT,
    @supplier_id INT,
    @lines INT = 5,            -- 3–8 typical
    @seed INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    DECLARE @order_date DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @po_number NVARCHAR(30) = CONCAT('PO-', FORMAT(ABS(CHECKSUM(NEWID())), '000000000'));

    INSERT INTO zava.PurchaseOrder (po_number, supplier_id, store_id, order_date, expected_delivery_date, status)
    VALUES (@po_number, @supplier_id, @store_id, @order_date, DATEADD(DAY, 3 + ABS(CHECKSUM(NEWID())) % 7, @order_date), 'APPROVED');

    DECLARE @po_id BIGINT = SCOPE_IDENTITY();

    ;WITH Pick AS
    (
        SELECT TOP (@lines)
            sp.product_id,
            sp.price_eur,
            CAST(5 + (ABS(CHECKSUM(NEWID())) % 45) AS DECIMAL(12,3)) AS qty
        FROM zava.SupplierProduct AS sp
        WHERE sp.supplier_id = @supplier_id
        ORDER BY NEWID()
    )
    INSERT INTO zava.PurchaseOrderLine (po_id, product_id, qty_ordered, unit_price_eur)
    SELECT @po_id, product_id, qty, price_eur
    FROM Pick;

    COMMIT;
END;
GO

/* Receive Delivery */
IF OBJECT_ID('zava.usp_ReceiveDelivery','P') IS NOT NULL
    DROP PROCEDURE zava.usp_ReceiveDelivery;
GO
CREATE PROCEDURE zava.usp_ReceiveDelivery
    @po_id BIGINT,
    @damage_rate FLOAT = 0.02
AS
BEGIN
    SET NOCOUNT ON;
