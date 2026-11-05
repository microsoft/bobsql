-- Batch UPDATE by Category: updates ~2500 rows per execution, heavy version generation
SET NOCOUNT ON;
DECLARE @Category INT = ABS(CHECKSUM(NEWID())) % 20;
DECLARE @Amount DECIMAL(18,2) = CAST((ABS(CHECKSUM(NEWID())) % 100) AS DECIMAL(18,2)) / 100.0;
UPDATE dbo.StressAccounts
SET Balance = Balance + @Amount,
    LastUpdated = SYSUTCDATETIME()
WHERE Category = @Category;
