-- ============================================================================
-- OLTP Stress Setup: stress_adr_rcsi_ol (RCSI ON, ADR ON, OL ON)
-- ============================================================================
USE master;
GO
IF DB_ID(N'stress_adr_rcsi_ol') IS NOT NULL
BEGIN
    ALTER DATABASE stress_adr_rcsi_ol SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE stress_adr_rcsi_ol;
END
GO
CREATE DATABASE stress_adr_rcsi_ol;
GO
ALTER DATABASE stress_adr_rcsi_ol SET RECOVERY SIMPLE;
ALTER DATABASE stress_adr_rcsi_ol SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE stress_adr_rcsi_ol SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE stress_adr_rcsi_ol SET OPTIMIZED_LOCKING = ON;
GO
USE stress_adr_rcsi_ol;
GO
-- Accounts: 50K rows, wider rows (~180 bytes), 4 NCIs to amplify version cost
CREATE TABLE dbo.Accounts
(
    AccountId          INT           NOT NULL IDENTITY(1,1),
    AccountName        NVARCHAR(50)  NOT NULL,
    Email              NVARCHAR(100) NOT NULL,
    Phone              VARCHAR(20)   NOT NULL,
    CreditScore        INT           NOT NULL DEFAULT 650,
    CreditLimit        DECIMAL(18,2) NOT NULL DEFAULT 5000.00,
    Balance            DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    PendingBalance     DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    TotalDebits        DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    TotalCredits       DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    TransactionCount   INT           NOT NULL DEFAULT 0,
    LastTransactionDate DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME(),
    AccountStatus      TINYINT       NOT NULL DEFAULT 1,
    Category           INT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_Accounts PRIMARY KEY CLUSTERED (AccountId)
);
GO
CREATE NONCLUSTERED INDEX IX_Accounts_Email ON dbo.Accounts(Email);
CREATE NONCLUSTERED INDEX IX_Accounts_Status_Category ON dbo.Accounts(AccountStatus, Category) INCLUDE (Balance, CreditLimit);
CREATE NONCLUSTERED INDEX IX_Accounts_LastTransaction ON dbo.Accounts(LastTransactionDate) INCLUDE (AccountName, Balance);
CREATE NONCLUSTERED INDEX IX_Accounts_CreditScore ON dbo.Accounts(CreditScore) INCLUDE (CreditLimit, Balance);
GO
INSERT INTO dbo.Accounts (AccountName, Email, Phone, CreditScore, CreditLimit, Balance, Category)
SELECT
    N'Acct_' + CAST(v.n AS NVARCHAR(10)),
    N'user' + CAST(v.n AS NVARCHAR(10)) + N'@contoso.com',
    '555-' + RIGHT('0000000' + CAST(v.n AS VARCHAR(7)), 7),
    600 + (ABS(CHECKSUM(NEWID())) % 200),
    CAST((ABS(CHECKSUM(NEWID())) % 50000) AS DECIMAL(18,2)),
    CAST(ABS(CHECKSUM(NEWID())) % 100000 AS DECIMAL(18,2)) / 100.0,
    ABS(CHECKSUM(NEWID())) % 20
FROM (
    SELECT TOP (50000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
) v;
GO
-- Orders: insert/update/delete churn, wider rows (~250 bytes), 2 NCIs
CREATE TABLE dbo.Orders
(
    CustomerId      INT           NOT NULL,
    OrderId         INT           NOT NULL IDENTITY(1,1),
    Amount          DECIMAL(18,2) NOT NULL,
    Tax             DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    OrderStatus     TINYINT       NOT NULL DEFAULT 1,
    ItemCount       INT           NOT NULL DEFAULT 1,
    ItemDescription NVARCHAR(200) NOT NULL,
    ShippingAddress NVARCHAR(200) NOT NULL,
    OrderDate       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    ShipDate        DATETIME2     NULL,
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (CustomerId, OrderId)
);
GO
CREATE NONCLUSTERED INDEX IX_Orders_Status ON dbo.Orders(OrderStatus) INCLUDE (Amount, OrderDate);
CREATE NONCLUSTERED INDEX IX_Orders_Date ON dbo.Orders(OrderDate) INCLUDE (CustomerId, Amount);
GO
PRINT N'stress_adr_rcsi_ol: Accounts 50K rows (4 NCIs), Orders empty (2 NCIs). Config: RCSI ON, ADR ON, OL ON';
GO
