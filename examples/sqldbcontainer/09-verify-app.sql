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

DECLARE @CustomerId int = (SELECT MIN(CustomerId) FROM dbo.Customers);
DECLARE @New TABLE (CaseId int);
DECLARE @CaseId int, @Version binary(8), @Impersonating bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    IF HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'UNMASK') <> 0
       OR HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'SELECT') <> 0
       OR HAS_PERMS_BY_NAME('dbo.Cases', 'OBJECT', 'UPDATE') <> 0
        THROW 51105, 'Web role has excess data permissions.', 1;
    INSERT @New EXEC dbo.CreateCase @CustomerId = @CustomerId,
        @Title = N'Web procedure verification', @Description = N'Synthetic rollback-only test.',
        @Details = N'{"channel":"web","extra":{"preserve":true}}';
    REVERT;
    SET @Impersonating = 0;
    SELECT @CaseId = CaseId FROM @New;
    SELECT @Version = Version FROM dbo.Cases WHERE CaseId = @CaseId;
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    EXEC dbo.UpdateCase @CaseId = @CaseId, @Version = @Version,
        @Title = N'Web procedure verification', @Description = N'Synthetic rollback-only test.',
        @Resolution = N'Verified procedure-based save.', @Topic = 'general',
        @Status = 'Resolved', @Priority = 'High',
        @Details = N'{"channel":"chat","extra":{"preserve":true}}';
    REVERT;
    SET @Impersonating = 0;
    IF NOT EXISTS (SELECT 1 FROM dbo.Cases WHERE CaseId = @CaseId
                   AND Status = 'Resolved' AND Priority = 'High'
                   AND JSON_VALUE(Details, '$.channel') = 'chat'
                   AND JSON_VALUE(Details, '$.extra.preserve') = 'true')
        THROW 51105, 'Web update failed to preserve native JSON fields.', 1;
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    EXEC dbo.UpdateCase @CaseId = @CaseId, @Version = @Version,
        @Title = N'Must not overwrite', @Description = N'Stale version.',
        @Resolution = NULL, @Topic = 'general', @Status = 'Open', @Priority = 'Normal',
        @Details = N'{"channel":"web"}';
    THROW 51105, 'Stale rowversion unexpectedly overwrote a newer case.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF @Impersonating = 1 REVERT;
    SET @Impersonating = 0;
    IF ERROR_NUMBER() <> 51103 THROW;
END CATCH;
IF EXISTS (SELECT 1 FROM dbo.Cases WHERE CaseId = @CaseId)
    THROW 51105, 'Rollback-only web test left a case behind.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    EXEC dbo.CreateCase @CustomerId = @CustomerId,
        @Title = N'Invalid JSON test', @Description = N'Must not insert.',
        @Details = N'{"channel":"email"}';
    THROW 51105, 'Unsupported JSON channel unexpectedly accepted.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF @Impersonating = 1 REVERT;
    SET @Impersonating = 0;
    IF ERROR_NUMBER() <> 51100 THROW;
END CATCH;

BEGIN TRY
    BEGIN TRANSACTION;
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    EXEC dbo.CreateCase @CustomerId = @CustomerId,
        @Title = N'Unresolved resolution test', @Description = N'Must not insert.',
        @Status = 'Resolved', @Details = N'{"channel":"web"}';
    THROW 51105, 'Resolved case without a resolution unexpectedly accepted.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF @Impersonating = 1 REVERT;
    IF ERROR_NUMBER() <> 51100 THROW;
END CATCH;
SELECT 'PASS: restricted create/update, native JSON, stale-write rejection, input validation; test rows rolled back.' AS Verification;

DECLARE @ProfileId int, @QueryJson nvarchar(max);
SELECT TOP (1) @ProfileId = e.ProfileId, @QueryJson = CAST(e.Embedding AS nvarchar(max))
FROM dbo.QueryEmbeddings AS e
INNER JOIN dbo.DemoConfiguration AS d ON d.ActiveProfileId = e.ProfileId
ORDER BY e.PreparedSearchId;
IF @QueryJson IS NULL THROW 51105, 'No active prepared vector is available for live-path verification.', 1;
DECLARE @LiveHits TABLE
(
    CaseId int, Title nvarchar(200), Resolution nvarchar(2000),
    Topic varchar(40), Status varchar(20), CosineDistance float
);
BEGIN TRY
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    INSERT @LiveHits EXEC dbo.SearchLiveCases @ProfileId = @ProfileId, @QueryJson = @QueryJson;
    REVERT;
    SET @Impersonating = 0;
END TRY
BEGIN CATCH
    IF @Impersonating = 1 REVERT;
    THROW;
END CATCH;
IF (SELECT COUNT(*) FROM @LiveHits WHERE Status = 'Resolved') <> 5
    THROW 51105, 'Live vector procedure did not return five resolved cases under the restricted role.', 1;
BEGIN TRY
    EXECUTE AS USER = 'CustomerServiceDeskVerifier';
    SET @Impersonating = 1;
    EXEC dbo.SearchLiveCases @ProfileId = -1, @QueryJson = @QueryJson;
    THROW 51105, 'Live search unexpectedly accepted a different embedding profile.', 1;
END TRY
BEGIN CATCH
    IF @Impersonating = 1 REVERT;
    IF ERROR_NUMBER() <> 51102 THROW;
END CATCH;
SELECT 'PASS: restricted live vector search and profile-change rejection.' AS Verification;
