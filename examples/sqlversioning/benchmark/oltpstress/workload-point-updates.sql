-- Account transaction: debit + settle in explicit transaction
-- Touches Balance, CreditScore, LastTransactionDate, AccountStatus → versions on CI + 4 NCIs
SET NOCOUNT ON;
DECLARE @AccountId INT = (ABS(CHECKSUM(NEWID())) % 50000) + 1;
DECLARE @Amount DECIMAL(18,2) = CAST((ABS(CHECKSUM(NEWID())) % 10000) AS DECIMAL(18,2)) / 100.0;

BEGIN TRAN;
    -- Debit: touches Balance, PendingBalance, TotalDebits, TransactionCount, LastTransactionDate, CreditScore
    UPDATE dbo.Accounts
    SET Balance = Balance - @Amount,
        PendingBalance = PendingBalance + @Amount,
        TotalDebits = TotalDebits + @Amount,
        TransactionCount = TransactionCount + 1,
        LastTransactionDate = SYSUTCDATETIME(),
        CreditScore = CASE WHEN Balance - @Amount < 0 THEN CreditScore - 1 ELSE CreditScore END
    WHERE AccountId = @AccountId;

    -- Settle: touches PendingBalance, TotalCredits, AccountStatus
    UPDATE dbo.Accounts
    SET PendingBalance = 0,
        TotalCredits = TotalCredits + @Amount,
        AccountStatus = CASE WHEN Balance < 0 THEN 2 ELSE 1 END
    WHERE AccountId = @AccountId;
COMMIT;
