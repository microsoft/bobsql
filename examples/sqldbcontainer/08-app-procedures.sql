USE CustomerServiceDesk;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.GetCustomers
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CustomerId, DisplayName FROM dbo.Customers ORDER BY DisplayName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetPreparedSearches
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PreparedSearchId, SearchText FROM dbo.PreparedSearches ORDER BY SearchCode;
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetDeskEnvironment
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProfileId int, @Prefix nvarchar(50);
    SELECT @ProfileId = d.ActiveProfileId, @Prefix = p.DocumentPrefix
    FROM dbo.DemoConfiguration AS d
    LEFT JOIN dbo.EmbeddingProfiles AS p ON p.ProfileId = d.ActiveProfileId
    WHERE d.ConfigurationId = 1;
    SELECT DB_NAME() AS DatabaseName, USER_NAME() AS DatabaseUser,
        CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS Edition,
        CAST(SERVERPROPERTY('EngineEdition') AS int) AS EngineEdition,
        CAST(@@VERSION AS nvarchar(1000)) AS EngineVersion,
        (SELECT COUNT(*) FROM dbo.Cases) AS TotalCases,
        (SELECT COUNT(*) FROM dbo.Cases WHERE Status = 'Open') AS OpenCases,
        (SELECT COUNT(*) FROM dbo.Cases WHERE Status = 'InProgress') AS InProgressCases,
        (SELECT COUNT(*) FROM dbo.Cases WHERE Status = 'Resolved') AS ResolvedCases,
        (SELECT COUNT(*) FROM dbo.CaseEmbeddingInputs AS i
         LEFT JOIN dbo.CaseEmbeddings AS e ON e.CaseId = i.CaseId AND e.ProfileId = @ProfileId
         WHERE e.EmbeddingId IS NULL
            OR e.InputHash <> HASHBYTES('SHA2_256', CONCAT(@Prefix, i.InputText))) AS PendingEmbeddings,
        p.ProfileName, p.ModelName, p.ModelVersion, p.Dimensions,
        (SELECT COUNT(*) FROM dbo.QueryEmbeddings AS e
         INNER JOIN dbo.PreparedSearches AS s ON s.PreparedSearchId = e.PreparedSearchId
         WHERE e.ProfileId = @ProfileId
           AND e.InputHash = HASHBYTES('SHA2_256', CONCAT(p.QueryPrefix, s.SearchText))) AS ReadyQueries,
        (SELECT COUNT(*) FROM dbo.PreparedSearches) AS TotalQueries,
        CAST(CASE WHEN EXISTS (SELECT 1 FROM sys.indexes
             WHERE object_id = OBJECT_ID(N'dbo.Cases') AND name = N'IX_Cases_Details'
               AND is_disabled = 0) THEN 1 ELSE 0 END AS bit) AS JsonIndexPresent,
        (SELECT JSON_VALUE(build_parameters, '$.Version') FROM sys.vector_indexes
         WHERE object_id = OBJECT_ID(N'dbo.CaseEmbeddings')
           AND name = N'IX_CaseEmbeddings_Vector') AS VectorIndexVersion,
        CAST((SELECT value FROM sys.database_scoped_configurations
              WHERE name = 'PREVIEW_FEATURES') AS int) AS PreviewFeatures,
        HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'UNMASK') AS CanUnmask,
        HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'SELECT') AS CanReadCustomers
    FROM (VALUES (1)) AS singleton(Id)
    LEFT JOIN dbo.EmbeddingProfiles AS p ON p.ProfileId = @ProfileId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetSearchProfile
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.ProfileId, p.Provider, p.ModelName, p.ModelVersion, p.Dimensions, p.QueryPrefix
    FROM dbo.DemoConfiguration AS d
    INNER JOIN dbo.EmbeddingProfiles AS p ON p.ProfileId = d.ActiveProfileId
    WHERE d.ConfigurationId = 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SearchLiveCases
    @ProfileId int,
    @QueryJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Query vector(768) = CAST(@QueryJson AS vector(768));
    EXEC dbo.SearchCaseVectors @ProfileId = @ProfileId, @Query = @Query;
END;
GO

CREATE OR ALTER PROCEDURE dbo.ValidateCaseInput
    @Title nvarchar(200), @Description nvarchar(2000), @Resolution nvarchar(2000),
    @Topic varchar(40), @Status varchar(20), @Priority varchar(10), @Details nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    IF NULLIF(TRIM(@Title), N'') IS NULL OR NULLIF(TRIM(@Description), N'') IS NULL
       OR NULLIF(TRIM(@Topic), '') IS NULL
        THROW 51100, 'Title, description, and topic are required.', 1;
    IF @Status IS NULL OR @Status NOT IN ('Open', 'InProgress', 'Resolved')
       OR @Priority IS NULL OR @Priority NOT IN ('Low', 'Normal', 'High')
        THROW 51100, 'Choose a valid status and priority.', 1;
    IF @Status = 'Resolved' AND NULLIF(TRIM(@Resolution), N'') IS NULL
        THROW 51100, 'A resolved case requires a resolution.', 1;
    IF COALESCE(ISJSON(@Details, OBJECT), 0) <> 1 OR DATALENGTH(@Details) > 16000
        THROW 51100, 'Details must be a JSON object of at most 8000 characters.', 1;
    IF JSON_VALUE(@Details, '$.channel') IS NULL
       OR JSON_VALUE(@Details, '$.channel') NOT IN ('web', 'phone', 'chat')
        THROW 51100, 'JSON details need a channel of web, phone, or chat.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.CreateCase
    @CustomerId int, @Title nvarchar(200), @Description nvarchar(2000),
    @Resolution nvarchar(2000) = NULL, @Topic varchar(40) = 'general',
    @Status varchar(20) = 'Open', @Priority varchar(10) = 'Normal', @Details nvarchar(max) = N'{}'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ANSI_WARNINGS ON;
    SET ANSI_PADDING ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;
    EXEC dbo.ValidateCaseInput @Title, @Description, @Resolution, @Topic, @Status, @Priority, @Details;
    IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerId = @CustomerId)
        THROW 51100, 'Choose an existing synthetic customer.', 1;
    INSERT dbo.Cases (CustomerId, Title, Description, Resolution, Topic, Status, Priority, Details)
    OUTPUT inserted.CaseId
    VALUES (@CustomerId, @Title, @Description, @Resolution, @Topic, @Status, @Priority, CAST(@Details AS json));
END;
GO

CREATE OR ALTER PROCEDURE dbo.UpdateCase
    @CaseId int, @Version binary(8), @Title nvarchar(200), @Description nvarchar(2000),
    @Resolution nvarchar(2000), @Topic varchar(40), @Status varchar(20),
    @Priority varchar(10), @Details nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ANSI_WARNINGS ON;
    SET ANSI_PADDING ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;
    EXEC dbo.ValidateCaseInput @Title, @Description, @Resolution, @Topic, @Status, @Priority, @Details;
    UPDATE dbo.Cases
    SET Title = @Title, Description = @Description, Resolution = @Resolution,
        Topic = @Topic, Status = @Status, Priority = @Priority, Details = CAST(@Details AS json),
        UpdatedAt = SYSUTCDATETIME()
    WHERE CaseId = @CaseId AND Version = @Version;
    IF @@ROWCOUNT = 0
        THROW 51103, 'This case changed or was removed. Reload it before saving; your changes were not applied.', 1;
END;
GO

GRANT EXECUTE ON dbo.GetCustomers TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.GetPreparedSearches TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.GetSearchProfile TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.SearchLiveCases TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.GetDeskEnvironment TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.CreateCase TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.UpdateCase TO CustomerServiceDeskApp;
GRANT VIEW DEFINITION ON OBJECT::dbo.Cases TO CustomerServiceDeskApp;
GRANT VIEW DEFINITION ON OBJECT::dbo.CaseEmbeddings TO CustomerServiceDeskApp;
GO
