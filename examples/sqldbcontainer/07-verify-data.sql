USE CustomerServiceDesk;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

IF (SELECT COUNT(*) FROM dbo.Customers WHERE CustomerCode LIKE 'DEMO-C%') <> 100
    THROW 51105, 'Expected 100 seeded synthetic customers.', 1;
IF (SELECT COUNT(*) FROM dbo.Cases WHERE SeedKey LIKE 'DEMO-CASE-%') <> 1000
    THROW 51105, 'Expected 1000 seeded support cases.', 1;
IF (SELECT COUNT(*) FROM dbo.PreparedSearches) < 6
    THROW 51105, 'Expected at least six prepared searches.', 1;
IF EXISTS (SELECT 1 FROM dbo.CaseEmbeddingInputs
           WHERE InputText LIKE N'%@example.test%' OR InputText LIKE N'%202-555-%')
    THROW 51105, 'Embedding input unexpectedly contains synthetic contact information.', 1;

DECLARE @CaseId int = (SELECT CaseId FROM dbo.Cases WHERE SeedKey = 'DEMO-CASE-0001');
DECLARE @Masked TABLE
(
    CaseId int, CustomerId int, Title nvarchar(200), Description nvarchar(2000),
    Resolution nvarchar(2000), Topic varchar(40), Status varchar(20), Priority varchar(10),
    Details nvarchar(max), CreatedAt datetime2(0), UpdatedAt datetime2(0), Version binary(8),
    DisplayName nvarchar(100), Email varchar(255), Phone varchar(30)
);
DECLARE @Impersonating bit = 0;
BEGIN TRY
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    IF HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'UNMASK') <> 0
        THROW 51105, 'The application verifier has UNMASK permission.', 1;
    IF HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'SELECT') <> 0
        THROW 51105, 'The application verifier has direct customer-table access.', 1;
    INSERT @Masked EXEC dbo.GetCase @CaseId = @CaseId;
    REVERT;
    SET @Impersonating = 0;
END TRY
BEGIN CATCH
    IF @Impersonating = 1 REVERT;
    THROW;
END CATCH;
IF NOT EXISTS (SELECT 1 FROM @Masked WHERE Email = '*****@example.test' AND Phone = '(+1)-xxxx')
    THROW 51105, 'The application procedure did not return regex-masked contacts.', 1;

DECLARE @Hits TABLE
(
    CaseId int, Title nvarchar(200), Resolution nvarchar(2000),
    Topic varchar(40), Status varchar(20), CosineDistance float
);
DECLARE @Results TABLE (SearchCode varchar(30), ExpectedTopic varchar(40), MatchesInTop5 int);
DECLARE @SearchId int = 0, @Code varchar(30), @Expected varchar(40);
WHILE EXISTS (SELECT 1 FROM dbo.PreparedSearches WHERE PreparedSearchId > @SearchId)
BEGIN
    SELECT TOP (1) @SearchId = PreparedSearchId, @Code = SearchCode, @Expected = ExpectedTopic
    FROM dbo.PreparedSearches WHERE PreparedSearchId > @SearchId ORDER BY PreparedSearchId;
    DELETE FROM @Hits;
    BEGIN TRY
        EXECUTE AS USER = 'CustomerServiceDeskVerifier';
        SET @Impersonating = 1;
        INSERT @Hits EXEC dbo.SearchPreparedCases @PreparedSearchId = @SearchId, @Take = 5;
        REVERT;
        SET @Impersonating = 0;
    END TRY
    BEGIN CATCH
        IF @Impersonating = 1 REVERT;
        THROW;
    END CATCH;
    IF (SELECT COUNT(*) FROM @Hits) <> 5
        THROW 51105, 'Prepared semantic search did not return five resolved cases.', 1;
    IF (SELECT COUNT(*) FROM @Hits WHERE Topic = @Expected AND Status = 'Resolved') < 3
    BEGIN
        DECLARE @Error nvarchar(2048) = CONCAT('Prepared search ', @Code, ' returned fewer than three expected-topic matches in its top five.');
        THROW 51105, @Error, 1;
    END;
    INSERT @Results SELECT @Code, @Expected, COUNT(*) FROM @Hits WHERE Topic = @Expected;
END;

BEGIN TRY
    -- This transaction exists solely to restore the case after testing stale-vector rejection.
    BEGIN TRANSACTION;
    UPDATE dbo.Cases SET Description = CONCAT(Description, N' Stale-vector verification marker.')
    WHERE CaseId = @CaseId;
    EXEC dbo.SearchPreparedCases @PreparedSearchId = @SearchId;
    THROW 51105, 'Search accepted stale case embeddings.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() <> 51102 THROW;
END CATCH;

SELECT SearchCode, ExpectedTopic, MatchesInTop5 FROM @Results ORDER BY SearchCode;
