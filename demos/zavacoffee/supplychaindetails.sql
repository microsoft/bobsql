-- Target: Fabric SQL Database
-- Schema and table to hold ~3 TB of test data as large LOBs

IF SCHEMA_ID(N'zava') IS NULL
    EXEC('CREATE SCHEMA zava');

IF OBJECT_ID(N'zava.supplychaindetails','U') IS NOT NULL
    DROP TABLE zava.supplychaindetails;

-- HEAP = cheaper insert path; add indexes later if you really need them.
CREATE TABLE zava.supplychaindetails
(
    supplychain_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY, -- narrow clustered PK
    sku            CHAR(20)           NOT NULL,               -- small attributes for realism
    location_id    INT                NOT NULL,
    event_dt_utc   DATETIME2(3)       NOT NULL CONSTRAINT DF_scd_evt DEFAULT SYSUTCDATETIME(),
    payload        VARBINARY(MAX)     NOT NULL                -- big LOB to reach size fast
);

/* =========================================================================
   Fabric SQL Database
   Fill zava.supplychaindetails up to a target size (MB), with progress logging
   -------------------------------------------------------------------------
   Knobs to tune:
     @target_mb               -- total table size goal (MB). 3 TB ≈ 3*1024*1024 MB
     @payload_mb              -- MB per row (LOB size). Larger payload = fewer rows to hit target
     @rows_per_batch          -- rows per transaction; each batch commits to cap log footprint
     @progress_every_batches  -- write a heartbeat row every N batches
     @sleep_ms                -- optional throttle between batches (0 = none)
     @run_notes               -- free‑text note stored with the run header
   ========================================================================= */

SET NOCOUNT ON;

DECLARE @target_mb               BIGINT = 1 * 1024 * 1024;  -- 3 TB in MB (change as needed)
DECLARE @payload_mb              INT    = 8;                -- MB per inserted row (LOB)
DECLARE @rows_per_batch          INT    = 64;               -- commit frequency
DECLARE @progress_every_batches  INT    = 20;               -- heartbeat interval
DECLARE @sleep_ms                INT    = 0;                -- throttle (ms) between batches
DECLARE @run_notes               NVARCHAR(200) = N'3TB fill test with batched LOB payload';

/* -------------------------------------------------------------------------
   0) Schema + metadata tables for progress logging
   ------------------------------------------------------------------------- */
IF SCHEMA_ID(N'zava') IS NULL
    EXEC('CREATE SCHEMA zava');

IF OBJECT_ID(N'zava.LoadRun','U') IS NULL
BEGIN
    CREATE TABLE zava.LoadRun
    (
        run_id          INT IDENTITY(1,1) PRIMARY KEY,
        started_utc     DATETIME2(3) NOT NULL CONSTRAINT DF_LoadRun_start DEFAULT SYSUTCDATETIME(),
        completed_utc   DATETIME2(3) NULL,
        target_mb       BIGINT       NOT NULL,
        payload_mb      INT          NOT NULL,
        rows_per_batch  INT          NOT NULL,
        progress_every_batches INT   NOT NULL,
        notes           NVARCHAR(200) NULL
    );
END;

IF OBJECT_ID(N'zava.LoadHeartbeat','U') IS NULL
BEGIN
    CREATE TABLE zava.LoadHeartbeat
    (
        run_id          INT          NOT NULL,
        batch_no        BIGINT       NOT NULL,
        logged_utc      DATETIME2(3) NOT NULL CONSTRAINT DF_LoadHeartbeat_log DEFAULT SYSUTCDATETIME(),
        approx_size_mb  DECIMAL(38,4) NOT NULL,
        total_rows      BIGINT        NOT NULL,
        CONSTRAINT FK_LoadHeartbeat_Run FOREIGN KEY (run_id)
            REFERENCES zava.LoadRun(run_id)
    );
END;

/* -------------------------------------------------------------------------
   1) Target table: keep it HEAP (cheap inserts). Add indexes AFTER the load.
      We add a small nonclustered PRIMARY KEY only for identity uniqueness.
   ------------------------------------------------------------------------- */
IF OBJECT_ID(N'zava.supplychaindetails','U') IS NULL
BEGIN
    CREATE TABLE zava.supplychaindetails
    (
        supplychain_id BIGINT         NOT NULL IDENTITY(1,1)
            CONSTRAINT PK_scd PRIMARY KEY NONCLUSTERED,   -- keep table heap (no clustered index)
        sku            CHAR(20)       NOT NULL,
        location_id    INT            NOT NULL,
        event_dt_utc   DATETIME2(3)   NOT NULL CONSTRAINT DF_scd_evt DEFAULT SYSUTCDATETIME(),
        payload        VARBINARY(MAX) NOT NULL
        -- no other indexes during load
    );
END;

/* -------------------------------------------------------------------------
   2) Insert a run header; capture run_id for heartbeats
   ------------------------------------------------------------------------- */
INSERT INTO zava.LoadRun(target_mb, payload_mb, rows_per_batch, progress_every_batches, notes)
VALUES (@target_mb, @payload_mb, @rows_per_batch, @progress_every_batches, @run_notes);

DECLARE @run_id INT = CONVERT(INT, SCOPE_IDENTITY());

/* -------------------------------------------------------------------------
   3) Precompute reusable payload = @payload_mb MB
   ------------------------------------------------------------------------- */
DECLARE @payload VARBINARY(MAX) =
    CONVERT(VARBINARY(MAX),
            REPLICATE(CONVERT(VARCHAR(MAX), 'X'), @payload_mb * 1024 * 1024));

/* -------------------------------------------------------------------------
   4) Batch loop until table reaches @target_mb (approx via allocation pages)
      size(MB) = (pages * 8 KB) / 1024 KB
   ------------------------------------------------------------------------- */
DECLARE @size_mb           DECIMAL(38,4);
DECLARE @batches_written   BIGINT  = 0;
DECLARE @rows_total        BIGINT;

-- quick sanity on existing rows
SELECT @rows_total = COUNT(*) FROM zava.supplychaindetails;

DECLARE @msg NVARCHAR(4000) =
       N'Run '            + CAST(@run_id AS NVARCHAR(20))
    +  N' started. target=' + CAST(@target_mb AS NVARCHAR(32)) + N' MB'
    +  N'; payload='        + CAST(@payload_mb AS NVARCHAR(10)) + N' MB'
    +  N'; rows/batch='     + CAST(@rows_per_batch AS NVARCHAR(10))
    +  N'; existing rows='  + CAST(@rows_total AS NVARCHAR(32));
PRINT @msg;

WHILE 1 = 1
BEGIN
    -- Current table size (MB)
    SELECT @size_mb =
      (SELECT (SUM(in_row_data_page_count + lob_used_page_count + row_overflow_used_page_count) * 8.0)
              / 1024.0
       FROM sys.dm_db_partition_stats
       WHERE object_id = OBJECT_ID(N'zava.supplychaindetails', N'U'));

    IF @size_mb IS NULL SET @size_mb = 0;
    IF @size_mb >= @target_mb BREAK;

    BEGIN TRY
        BEGIN TRAN;

        /* Build @rows_per_batch rows set‑based (no RBAR).
           If your environment restricts sys.* access, replace with a Tally/Numbers table. */
        ;WITH n AS
        (
            SELECT TOP (@rows_per_batch)
                   ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
            FROM sys.all_objects a
            CROSS JOIN sys.all_objects b
        )
        INSERT INTO zava.supplychaindetails WITH (TABLOCK)
            (sku, location_id, payload)
        SELECT
            RIGHT('SKU' + CONVERT(VARCHAR(32), ABS(CHECKSUM(NEWID()))), 20),
            ABS(CHECKSUM(NEWID())) % 100000,
            @payload
        FROM n;

        COMMIT TRAN;
        SET @batches_written += 1;

        IF (@batches_written % @progress_every_batches = 0)
        BEGIN
            -- refresh counters for heartbeat
            SELECT @rows_total = COUNT(*) FROM zava.supplychaindetails;

            SELECT @size_mb =
              (SELECT (SUM(in_row_data_page_count + lob_used_page_count + row_overflow_used_page_count) * 8.0)
                      / 1024.0
               FROM sys.dm_db_partition_stats
               WHERE object_id = OBJECT_ID(N'zava.supplychaindetails', N'U'));

            INSERT INTO zava.LoadHeartbeat(run_id, batch_no, approx_size_mb, total_rows)
            VALUES (@run_id, @batches_written, @size_mb, @rows_total);

            DECLARE @hb NVARCHAR(4000) =
                   N'Heartbeat r=' + CAST(@run_id AS NVARCHAR(20))
                +  N' b='          + CAST(@batches_written AS NVARCHAR(20))
                +  N' size_mb='    + CAST(CAST(@size_mb AS DECIMAL(18,2)) AS NVARCHAR(32))
                +  N' rows='       + CAST(@rows_total AS NVARCHAR(32));
            PRINT @hb;
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(), @ErrNum INT = ERROR_NUMBER(), @ErrSt INT = ERROR_STATE();
        -- log the error heartbeat for post‑mortem
        SELECT @rows_total = COUNT(*) FROM zava.supplychaindetails;
        SELECT @size_mb =
          (SELECT (SUM(in_row_data_page_count + lob_used_page_count + row_overflow_used_page_count) * 8.0)
                  / 1024.0
           FROM sys.dm_db_partition_stats
           WHERE object_id = OBJECT_ID(N'zava.supplychaindetails', N'U'));
        INSERT INTO zava.LoadHeartbeat(run_id, batch_no, approx_size_mb, total_rows)
        VALUES (@run_id, @batches_written, ISNULL(@size_mb,0), ISNULL(@rows_total,0));
        THROW @ErrNum, @ErrMsg, @ErrSt;
    END CATCH;

    -- Optional throttle: build a TIME(3) variable for WAITFOR DELAY (no TIMEFROMPARTS)
    IF @sleep_ms > 0
    BEGIN
        DECLARE @delay TIME(3) = DATEADD(MILLISECOND, @sleep_ms, CAST('00:00:00' AS TIME(3)));
        WAITFOR DELAY @delay;
    END
END

-- Finalize the run header
UPDATE zava.LoadRun
   SET completed_utc = SYSUTCDATETIME()
 WHERE run_id = @run_id;

-- Final report
SELECT
    run_id          = @run_id,
    target_mb       = @target_mb,
    approx_size_mb  =
        (SELECT (SUM(in_row_data_page_count + lob_used_page_count + row_overflow_used_page_count) * 8.0)
                / 1024.0
         FROM sys.dm_db_partition_stats
         WHERE object_id = OBJECT_ID(N'zava.supplychaindetails','U')),
    total_rows      = (SELECT COUNT(*) FROM zava.supplychaindetails),
    batches_written = @batches_written,
    payload_mb      = @payload_mb,
    rows_per_batch  = @rows_per_batch,
    progress_every_batches = @progress_every_batches;