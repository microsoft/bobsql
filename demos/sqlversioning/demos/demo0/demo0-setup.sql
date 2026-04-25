-- ============================================================================
-- DEMO 0 — Setup for SQL Server Versioning Explained
-- Run this ONCE before the session to prepare all demo databases and objects.
-- Idempotent: safe to re-run.
-- Requires: SQL Server 2025 (or Azure SQL Database for OL demos)
-- ============================================================================
SET NOCOUNT ON;
GO

USE master;
GO

-- ============================================================================
-- 1. Demo database: texasrangerswillwinitthisyear (primary demos D1, D3, D4, D5, D6, D7)
-- ============================================================================
IF DB_ID(N'texasrangerswillwinitthisyear') IS NOT NULL
BEGIN
    ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE texasrangerswillwinitthisyear;
END
GO
CREATE DATABASE texasrangerswillwinitthisyear;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET RECOVERY SIMPLE;
GO
USE texasrangerswillwinitthisyear;
GO

-- Main demo table — Accounts
DROP TABLE IF EXISTS dbo.Accounts;
GO
CREATE TABLE dbo.Accounts
(
    AccountId   INT          NOT NULL IDENTITY(1,1),
    AccountName NVARCHAR(50) NOT NULL,
    Balance     DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    Status      NVARCHAR(20)  NOT NULL DEFAULT N'Active',
    LastUpdated DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    Filler      CHAR(100)     NOT NULL DEFAULT 'Standard retail checking. Branch referral. No overdraft protection. Monthly statement cycle.',
    CONSTRAINT PK_Accounts PRIMARY KEY CLUSTERED (AccountId)
);
GO

-- Seed 10,000 rows
INSERT INTO dbo.Accounts (AccountName, Balance, Status)
SELECT
    N'Account_' + CAST(v.n AS NVARCHAR(10)),
    CAST(ABS(CHECKSUM(NEWID())) % 100000 AS DECIMAL(18,2)) / 100.0,
    CASE WHEN v.n % 5 = 0 THEN N'Inactive' ELSE N'Active' END
FROM (
    SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
) v;
GO

-- FK demo tables (for D3 FK gotcha and D4 FK conflict)
DROP TABLE IF EXISTS dbo.OrderItems;
DROP TABLE IF EXISTS dbo.Orders;
GO
CREATE TABLE dbo.Orders
(
    OrderId     INT NOT NULL IDENTITY(1,1),
    AccountId   INT NOT NULL,
    OrderDate   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    Amount      DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderId),
    CONSTRAINT FK_Orders_Accounts FOREIGN KEY (AccountId) REFERENCES dbo.Accounts(AccountId)
);
GO
CREATE TABLE dbo.OrderItems
(
    ItemId      INT NOT NULL IDENTITY(1,1),
    OrderId     INT NOT NULL,
    ProductName NVARCHAR(50) NOT NULL,
    Quantity    INT NOT NULL DEFAULT 1,
    CONSTRAINT PK_OrderItems PRIMARY KEY CLUSTERED (ItemId),
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderId) REFERENCES dbo.Orders(OrderId)
);
GO
-- NOTE: Intentionally NO index on OrderItems.OrderId — used in D4 FK conflict demo
-- We add it later in the demo to show the fix

-- Seed some orders
INSERT INTO dbo.Orders (AccountId, Amount)
SELECT TOP (5000)
    (ABS(CHECKSUM(NEWID())) % 10000) + 1,
    CAST(ABS(CHECKSUM(NEWID())) % 10000 AS DECIMAL(18,2)) / 100.0
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
GO

INSERT INTO dbo.OrderItems (OrderId, ProductName, Quantity)
SELECT TOP (10000)
    (ABS(CHECKSUM(NEWID())) % 5000) + 1,
    N'Product_' + CAST(ABS(CHECKSUM(NEWID())) % 100 AS NVARCHAR(10)),
    (ABS(CHECKSUM(NEWID())) % 10) + 1
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
GO

-- Large table for ADR rollback demo (D5)
Drop TABLE IF EXISTS dbo.BigTable;
GO

-- ADR in-row vs off-row demo table (D4a)
-- ComplianceNotes CHAR(600) → rows are ~670 bytes → ~12 rows per page → pages
-- are packed tight with minimal free space. Even a narrow Balance update
-- can't fit an in-row version stub, forcing ADR to go off-row to PVS.
-- Contrast with Accounts in Beat 1 where the same update goes in-row.
DROP TABLE IF EXISTS dbo.SavingsAccounts;
GO
CREATE TABLE dbo.SavingsAccounts
(
    AccountId       INT            NOT NULL IDENTITY(1,1),
    AccountName     NVARCHAR(50)   NOT NULL,
    Balance         DECIMAL(18,2)  NOT NULL DEFAULT 0.00,
    Status          NVARCHAR(20)   NOT NULL DEFAULT N'Active',
    LastUpdated     DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    ComplianceNotes CHAR(600)      NOT NULL DEFAULT 'Account opened under standard KYC verification. Identity confirmed via government-issued photo ID and proof of address. Risk assessment completed with no adverse findings. Customer acknowledged terms of service, privacy policy, and electronic communications consent. Annual review scheduled. Documentation retained per federal regulatory retention requirements under 12 CFR Part 1010. AML screening passed.',
    -- Wide rows pack pages tight — no room for in-row version stubs
    CONSTRAINT PK_SavingsAccounts PRIMARY KEY CLUSTERED (AccountId)
);
GO
INSERT INTO dbo.SavingsAccounts (AccountName, Balance, Status)
SELECT TOP (100)
    N'Savings_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS NVARCHAR(10)),
    CAST(ABS(CHECKSUM(NEWID())) % 100000 AS DECIMAL(18,2)) / 100.0,
    CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 5 = 0 THEN N'Inactive' ELSE N'Active' END
FROM sys.all_objects;
GO

CREATE TABLE dbo.BigTable
(
    Id      INT NOT NULL IDENTITY(1,1),
    Val     INT NOT NULL DEFAULT 0,
    Payload CHAR(500) NOT NULL DEFAULT 'Batch load record. Source: OLTP-Primary. ETL validated. Checksum verified. Partition key assigned. Compression eligible. Retention: 7 years per regulatory mandate. Record ingested via nightly pipeline. Schema version 4.2. Data quality score: 98.7 percent. Upstream system: CoreBanking-East. Downstream consumers: Risk, Compliance, Reporting. Last audit: 2025-03-15. No exceptions flagged.',
    CONSTRAINT PK_BigTable PRIMARY KEY CLUSTERED (Id)
);
GO
INSERT INTO dbo.BigTable (Val)
SELECT TOP (500000) ABS(CHECKSUM(NEWID())) % 1000
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
GO

-- Benchmark table for D7
DROP TABLE IF EXISTS dbo.BenchAccounts;
GO
CREATE TABLE dbo.BenchAccounts
(
    AccountId   INT           NOT NULL IDENTITY(1,1),
    AccountName NVARCHAR(50)  NOT NULL,
    Balance     DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    Category    INT           NOT NULL DEFAULT 0,
    LastUpdated DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_BenchAccounts PRIMARY KEY CLUSTERED (AccountId)
);
GO
CREATE NONCLUSTERED INDEX IX_BenchAccounts_Category ON dbo.BenchAccounts(Category);
GO
INSERT INTO dbo.BenchAccounts (AccountName, Balance, Category)
SELECT
    N'Bench_' + CAST(v.n AS NVARCHAR(10)),
    CAST(ABS(CHECKSUM(NEWID())) % 100000 AS DECIMAL(18,2)) / 100.0,
    ABS(CHECKSUM(NEWID())) % 20
FROM (
    SELECT TOP (50000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
) v;
GO

-- ============================================================================
-- 2. Instance-wide impact databases (eaglesdontfly + howboutthemcowboys)
-- ============================================================================

-- The culprit database — opens a snapshot and forgets about it
IF DB_ID(N'eaglesdontfly') IS NOT NULL
BEGIN
    ALTER DATABASE eaglesdontfly SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE eaglesdontfly;
END
GO
CREATE DATABASE eaglesdontfly;
GO
ALTER DATABASE eaglesdontfly SET RECOVERY SIMPLE;
ALTER DATABASE eaglesdontfly SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE eaglesdontfly SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

USE eaglesdontfly;
GO
DROP TABLE IF EXISTS dbo.ReportData;
CREATE TABLE dbo.ReportData
(
    Id                INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Category          NVARCHAR(50) NOT NULL DEFAULT N'Eagles Season Recap',
    Score             INT NOT NULL DEFAULT 0,
    SuperBowlChances  INT NOT NULL DEFAULT 0,
    Notes             CHAR(500) NOT NULL DEFAULT 'Weekly scouting report: Defensive secondary continues to underperform in zone coverage. Opposing quarterbacks completing 72% of passes over the middle. Run defense remains top 10 but pass rush has declined since week 6. Special teams coverage units need work. Punt return average dropped to 6.2 yards. Coaching staff considering scheme adjustments for remaining schedule. Injury report: three starters questionable for next game.'
);
INSERT INTO dbo.ReportData (Category, Score, SuperBowlChances)
SELECT TOP (500000) 
    N'NFC East Standings', ABS(CHECKSUM(NEWID())) % 100, 0
FROM sys.all_columns a CROSS JOIN sys.all_columns b;
GO

-- The victim database — innocent OLTP, gets punished
IF DB_ID(N'howboutthemcowboys') IS NOT NULL
BEGIN
    ALTER DATABASE howboutthemcowboys SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE howboutthemcowboys;
END
GO
CREATE DATABASE howboutthemcowboys;
GO
ALTER DATABASE howboutthemcowboys SET RECOVERY SIMPLE;
ALTER DATABASE howboutthemcowboys SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE howboutthemcowboys SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

USE howboutthemcowboys;
GO
-- Wide table: char(7000) forces 1 row per page → maximum version store bloat
DROP TABLE IF EXISTS dbo.GameStats;
CREATE TABLE dbo.GameStats
(
    GameId   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Season   INT NOT NULL DEFAULT 2025,
    Opponent NVARCHAR(50) NOT NULL DEFAULT N'Philadelphia',
    Yards    INT NOT NULL DEFAULT 0,
    Padding  CHAR(7000) NOT NULL DEFAULT 'How bout them Cowboys'
);

-- 5000 rows × 1 row/page ≈ 5000 pages ≈ 40MB base table
SET NOCOUNT ON;
DECLARE @i INT = 1;
WHILE @i <= 5000
BEGIN
    INSERT INTO dbo.GameStats (Season, Opponent, Yards)
    VALUES (2025, 
            CASE @i % 4 
                WHEN 0 THEN N'Philadelphia'
                WHEN 1 THEN N'Washington' 
                WHEN 2 THEN N'NY Giants'
                ELSE N'Dallas Bye Week' 
            END,
            ABS(CHECKSUM(NEWID())) % 500);
    SET @i += 1;
END
SET NOCOUNT OFF;
GO

USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- 4. Verify setup
-- ============================================================================
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count,
    reserved_space_kb
FROM sys.dm_tran_version_store_space_usage
WHERE database_id IN (
    DB_ID(N'texasrangerswillwinitthisyear'), 
    DB_ID(N'eaglesdontfly'), DB_ID(N'howboutthemcowboys')
);

SELECT name, 
       is_read_committed_snapshot_on AS RCSI,
       snapshot_isolation_state_desc AS SnapshotIso,
       is_accelerated_database_recovery_on AS ADR
FROM sys.databases
WHERE name IN (
    N'texasrangerswillwinitthisyear', 
    N'eaglesdontfly', N'howboutthemcowboys'
);

PRINT N'=== SETUP COMPLETE ===';
PRINT N'Databases: texasrangerswillwinitthisyear, eaglesdontfly, howboutthemcowboys';
PRINT N'Tables: Accounts (10K), Orders (5K), OrderItems (10K), BigTable (500K), BenchAccounts (50K)';
PRINT N'        ReportData (500K in eaglesdontfly), GameStats (5K in howboutthemcowboys)';
PRINT N'Next: run each demo script in order (demo1 through demo7)';
GO
