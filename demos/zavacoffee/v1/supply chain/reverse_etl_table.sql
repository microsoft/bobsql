IF OBJECT_ID('zava.ReplenishmentProposal','U') IS NOT NULL
    DROP TABLE zava.ReplenishmentProposal;
GO
CREATE TABLE zava.ReplenishmentProposal
(
    proposal_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    asof_utc           DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    store_id           INT          NOT NULL,
    product_id         INT          NOT NULL,
    current_stock      DECIMAL(12,3) NOT NULL,
    reorder_point      DECIMAL(12,3) NOT NULL,
    safety_stock       DECIMAL(12,3) NOT NULL,
    recommended_qty    DECIMAL(12,3) NOT NULL,
    supplier_id        INT           NULL,
    unit_price_eur     DECIMAL(12,2) NULL,
    comment            NVARCHAR(200) NULL
);
GO