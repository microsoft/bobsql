-- Customers (can mirror from Corp or originate here)
CREATE TABLE loyalty.customer (
    customer_id     UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_loyalty_customer_id DEFAULT NEWSEQUENTIALID(),
    email           NVARCHAR(256)    NOT NULL UNIQUE,
    phone           NVARCHAR(32)     NULL,
    first_name      NVARCHAR(100)    NULL,
    last_name       NVARCHAR(100)    NULL,
    created_at_utc  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_loyalty_customer PRIMARY KEY (customer_id)
);

-- Loyalty accounts, 1:1 with customer by default
CREATE TABLE loyalty.loyalty_account (
    account_id      UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_loyalty_account_id DEFAULT NEWSEQUENTIALID(),
    customer_id     UNIQUEIDENTIFIER NOT NULL REFERENCES loyalty.customer(customer_id),
    tier_code       VARCHAR(32)      NOT NULL DEFAULT('BRONZE'), -- BRONZE/SILVER/GOLD/PLAT
    current_points  BIGINT           NOT NULL DEFAULT(0),
    last_activity_utc DATETIME2(3)   NULL,
    CONSTRAINT PK_loyalty_account PRIMARY KEY (account_id),
    UNIQUE (customer_id)
);

-- Points ledger (accruals/redemptions)
CREATE TABLE loyalty.points_ledger (
    entry_id        UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_loyalty_points_entry DEFAULT NEWSEQUENTIALID(),
    account_id      UNIQUEIDENTIFIER NOT NULL REFERENCES loyalty.loyalty_account(account_id),
    event_ts_utc    DATETIME2(3)     NOT NULL,
    source_system   VARCHAR(32)      NOT NULL, -- 'POS','MANUAL','PROMO'
    store_code      VARCHAR(16)      NULL,
    points_delta    INT              NOT NULL, -- +accrual, -redeem
    description     NVARCHAR(200)    NULL,
    reference_id    UNIQUEIDENTIFIER NULL,     -- link to pos_txn_id if POS
    CONSTRAINT PK_loyalty_points_ledger PRIMARY KEY (entry_id),
    INDEX IX_loyalty_points_account_ts (account_id, event_ts_utc)
);

-- Rewards & redemptions
CREATE TABLE loyalty.reward (
    reward_id       UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_loyalty_reward_id DEFAULT NEWSEQUENTIALID(),
    reward_code     VARCHAR(64)      NOT NULL UNIQUE,
    reward_name     NVARCHAR(200)    NOT NULL,
    points_cost     INT              NOT NULL CHECK (points_cost > 0),
    is_active       BIT              NOT NULL DEFAULT(1),
    CONSTRAINT PK_loyalty_reward PRIMARY KEY (reward_id)
);

CREATE TABLE loyalty.redemption (
    redemption_id   UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_loyalty_redeem_id DEFAULT NEWSEQUENTIALID(),
    account_id      UNIQUEIDENTIFIER NOT NULL REFERENCES loyalty.loyalty_account(account_id),
    reward_id       UNIQUEIDENTIFIER NOT NULL REFERENCES loyalty.reward(reward_id),
    redeemed_points INT              NOT NULL CHECK (redeemed_points > 0),
    store_code      VARCHAR(16)      NULL,
    event_ts_utc    DATETIME2(3)     NOT NULL,
    CONSTRAINT PK_loyalty_redemption PRIMARY KEY (redemption_id)
);

-- Offers & campaigns (simple)
CREATE TABLE loyalty.offer (
    offer_id        UNIQUEIDENTIFIER NOT NULL 
        CONSTRAINT DF_loyalty_offer_id DEFAULT NEWSEQUENTIALID(),
    offer_code      VARCHAR(64)      NOT NULL UNIQUE,
    offer_name      NVARCHAR(200)    NOT NULL,
    start_utc       DATETIME2(3)     NOT NULL,
    end_utc         DATETIME2(3)     NOT NULL,
    points_bonus    INT              NULL,
    is_active       AS (CASE WHEN SYSUTCDATETIME() BETWEEN start_utc AND end_utc THEN 1 ELSE 0 END) PERSISTED,
    CONSTRAINT PK_loyalty_offer PRIMARY KEY (offer_id)
);

CREATE TABLE loyalty.account_offer (
    account_id      UNIQUEIDENTIFIER NOT NULL REFERENCES loyalty.loyalty_account(account_id),
    offer_id        UNIQUEIDENTIFIER NOT NULL REFERENCES loyalty.offer(offer_id),
    assigned_utc    DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_loyalty_account_offer PRIMARY KEY (account_id, offer_id)
);
