USE CustomerServiceDesk;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;

IF OBJECT_ID(N'dbo.FeatureVerification', N'U') IS NOT NULL
    THROW 51000, 'FeatureVerification already exists; no objects were changed.', 1;
IF DATABASE_PRINCIPAL_ID(N'FeatureVerificationReader') IS NOT NULL
    THROW 51000, 'FeatureVerificationReader already exists; no objects were changed.', 1;

DECLARE @Impersonating bit = 0;
DECLARE @Masked TABLE (ID int, Email varchar(255));
DECLARE @Query vector(3) = '[1,0,0]';

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE dbo.FeatureVerification
    (
        ID int NOT NULL PRIMARY KEY,
        Email varchar(255) MASKED WITH
            (FUNCTION = 'REGEXP_REPLACE("^[^@]+", "*****")') NULL,
        Details json NOT NULL,
        Embedding vector(3) NOT NULL
    );

    INSERT dbo.FeatureVerification (ID, Email, Details, Embedding)
    VALUES
        (1, 'sample.customer@example.com', '{"channel":"web","product":"Router"}', '[1,0,0]'),
        (2, '', '{"channel":"phone","product":"Printer"}', '[0,1,0]'),
        (3, NULL, '{"channel":"web","product":"Laptop"}', '[-1,0,0]');

    IF (SELECT COUNT(*) FROM dbo.FeatureVerification
        WHERE JSON_VALUE(Details, '$.channel') = 'web') <> 2
        THROW 51001, 'Native JSON filtering did not return two web cases.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.FeatureVerification
        WHERE ABS(VECTOR_DISTANCE('cosine', @Query, Embedding) - (ID - 1)) > 0.000001
    )
        THROW 51002, 'Vector distances did not match the expected 0, 1, 2.', 1;

    DECLARE @NearestID int;
    SELECT TOP (1) @NearestID = ID
    FROM dbo.FeatureVerification
    ORDER BY VECTOR_DISTANCE('cosine', @Query, Embedding), ID;
    IF @NearestID <> 1
        THROW 51002, 'Exact vector search returned the wrong nearest row.', 1;

    IF (SELECT Email FROM dbo.FeatureVerification WHERE ID = 1) <> 'sample.customer@example.com'
        THROW 51003, 'The privileged baseline did not return the original email.', 1;

    CREATE USER FeatureVerificationReader WITHOUT LOGIN;
    GRANT SELECT ON dbo.FeatureVerification TO FeatureVerificationReader;

    EXECUTE AS USER = 'FeatureVerificationReader';
    SET @Impersonating = 1;
    IF HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'UNMASK') <> 0
        THROW 51003, 'The verification reader unexpectedly has UNMASK permission.', 1;
    INSERT @Masked (ID, Email)
        SELECT ID, Email FROM dbo.FeatureVerification;
    REVERT;
    SET @Impersonating = 0;

    IF NOT EXISTS (SELECT 1 FROM @Masked WHERE ID = 1 AND Email = '*****@example.com')
        THROW 51003, 'Regex masking did not hide the email username and preserve its domain.', 1;
    IF NOT EXISTS (SELECT 1 FROM @Masked WHERE ID = 2 AND Email = 'xxxx')
        THROW 51003, 'Empty-string masking differs from the verified preview build (xxxx).', 1;
    IF NOT EXISTS (SELECT 1 FROM @Masked WHERE ID = 3 AND Email IS NULL)
        THROW 51003, 'Regex masking changed the NULL test value.', 1;

    SELECT 'Native JSON filter' AS Test, 'PASS' AS Result, '2 web cases' AS Evidence
    UNION ALL
    SELECT 'Exact vector search', 'PASS', 'Cosine distances 0, 1, 2; nearest ID 1'
    UNION ALL
    SELECT 'Regex dynamic data masking', 'PASS', '*****@example.com; empty becomes xxxx; NULL preserved';

    -- Test fixtures and permissions must not become application schema.
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @Impersonating = 1
        REVERT;
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
