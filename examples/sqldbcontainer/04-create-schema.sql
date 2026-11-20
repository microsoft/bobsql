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

IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
CREATE TABLE dbo.Customers
(
    CustomerId int IDENTITY PRIMARY KEY,
    CustomerCode varchar(20) NOT NULL UNIQUE,
    DisplayName nvarchar(100) NOT NULL,
    Email varchar(255) MASKED WITH (FUNCTION = 'REGEXP_REPLACE("^[^@]+", "*****")') NOT NULL,
    Phone varchar(30) MASKED WITH (FUNCTION = 'REGEXP_REPLACE("(\+\d{1,3})(?:[ -.]?\d){7,14}", "(\1)-xxxx")') NOT NULL
);

IF OBJECT_ID(N'dbo.Cases', N'U') IS NULL
CREATE TABLE dbo.Cases
(
    CaseId int IDENTITY PRIMARY KEY,
    SeedKey varchar(30) NULL,
    CustomerId int NOT NULL REFERENCES dbo.Customers(CustomerId),
    Title nvarchar(200) NOT NULL,
    Description nvarchar(2000) NOT NULL,
    Resolution nvarchar(2000) NULL,
    Topic varchar(40) NOT NULL,
    Status varchar(20) NOT NULL CHECK (Status IN ('Open', 'InProgress', 'Resolved')),
    Priority varchar(10) NOT NULL CHECK (Priority IN ('Low', 'Normal', 'High')),
    Details json NOT NULL,
    CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    Version rowversion NOT NULL
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Cases') AND name = N'UX_Cases_SeedKey')
    CREATE UNIQUE INDEX UX_Cases_SeedKey ON dbo.Cases(SeedKey) WHERE SeedKey IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Cases') AND name = N'IX_Cases_Details')
    CREATE JSON INDEX IX_Cases_Details ON dbo.Cases(Details);

IF OBJECT_ID(N'dbo.EmbeddingProfiles', N'U') IS NULL
CREATE TABLE dbo.EmbeddingProfiles
(
    ProfileId int IDENTITY PRIMARY KEY,
    ProfileName varchar(100) NOT NULL UNIQUE,
    Provider varchar(20) NOT NULL,
    ModelName varchar(100) NOT NULL,
    ModelVersion varchar(100) NOT NULL,
    Dimensions int NOT NULL CHECK (Dimensions = 768),
    DocumentPrefix nvarchar(50) NOT NULL,
    QueryPrefix nvarchar(50) NOT NULL,
    CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID(N'dbo.CaseEmbeddings', N'U') IS NULL
CREATE TABLE dbo.CaseEmbeddings
(
    EmbeddingId int IDENTITY PRIMARY KEY CLUSTERED,
    ProfileId int NOT NULL REFERENCES dbo.EmbeddingProfiles(ProfileId),
    CaseId int NOT NULL REFERENCES dbo.Cases(CaseId),
    Embedding vector(768) NOT NULL,
    InputHash binary(32) NOT NULL,
    PreparedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    UNIQUE (ProfileId, CaseId)
);

IF OBJECT_ID(N'dbo.PreparedSearches', N'U') IS NULL
CREATE TABLE dbo.PreparedSearches
(
    PreparedSearchId int IDENTITY PRIMARY KEY,
    SearchCode varchar(30) NOT NULL UNIQUE,
    SearchText nvarchar(500) NOT NULL,
    ExpectedTopic varchar(40) NOT NULL
);

IF OBJECT_ID(N'dbo.QueryEmbeddings', N'U') IS NULL
CREATE TABLE dbo.QueryEmbeddings
(
    ProfileId int NOT NULL REFERENCES dbo.EmbeddingProfiles(ProfileId),
    PreparedSearchId int NOT NULL REFERENCES dbo.PreparedSearches(PreparedSearchId),
    Embedding vector(768) NOT NULL,
    InputHash binary(32) NOT NULL,
    PreparedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    PRIMARY KEY (ProfileId, PreparedSearchId)
);

IF OBJECT_ID(N'dbo.DemoConfiguration', N'U') IS NULL
CREATE TABLE dbo.DemoConfiguration
(
    ConfigurationId tinyint NOT NULL PRIMARY KEY CHECK (ConfigurationId = 1),
    ActiveProfileId int NULL REFERENCES dbo.EmbeddingProfiles(ProfileId)
);
IF NOT EXISTS (SELECT 1 FROM dbo.DemoConfiguration WHERE ConfigurationId = 1)
    INSERT dbo.DemoConfiguration (ConfigurationId) VALUES (1);
GO

CREATE OR ALTER VIEW dbo.CaseEmbeddingInputs
AS
SELECT CaseId,
    CONCAT(Title, NCHAR(10), Description, NCHAR(10), COALESCE(Resolution, N'')) AS InputText
FROM dbo.Cases;
GO

CREATE OR ALTER PROCEDURE dbo.GetCases
    @Status varchar(20) = NULL,
    @Channel nvarchar(20) = NULL,
    @Take int = 50
AS
BEGIN
    SET NOCOUNT ON;
    IF @Take NOT BETWEEN 1 AND 200
        THROW 51100, 'Take must be between 1 and 200.', 1;
    IF @Status IS NOT NULL AND @Status NOT IN ('Open', 'InProgress', 'Resolved')
        THROW 51100, 'Unknown case status.', 1;
    SELECT TOP (@Take) c.CaseId, c.Title, c.Topic, c.Status, c.Priority,
        u.DisplayName, JSON_VALUE(c.Details, '$.channel') AS Channel, c.UpdatedAt
    FROM dbo.Cases AS c INNER JOIN dbo.Customers AS u ON u.CustomerId = c.CustomerId
    WHERE (@Status IS NULL OR c.Status = @Status)
      AND (@Channel IS NULL OR JSON_VALUE(c.Details, '$.channel') = @Channel)
    ORDER BY c.UpdatedAt DESC, c.CaseId DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetCase
    @CaseId int
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Cases WHERE CaseId = @CaseId)
        THROW 51101, 'Case not found.', 1;
    SELECT c.CaseId, c.CustomerId, c.Title, c.Description, c.Resolution,
        c.Topic, c.Status, c.Priority, CAST(c.Details AS nvarchar(max)) AS Details,
        c.CreatedAt, c.UpdatedAt, c.Version, u.DisplayName, u.Email, u.Phone
    FROM dbo.Cases AS c INNER JOIN dbo.Customers AS u ON u.CustomerId = c.CustomerId
    WHERE c.CaseId = @CaseId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SearchCaseVectors
    @ProfileId int,
    @Query vector(768),
    @Take int = 5,
    @Status varchar(20) = 'Resolved'
AS
BEGIN
    SET NOCOUNT ON;
    IF @Take NOT BETWEEN 1 AND 20
        THROW 51100, 'Take must be between 1 and 20.', 1;
    IF @Status IS NOT NULL AND @Status NOT IN ('Open', 'InProgress', 'Resolved')
        THROW 51100, 'Unknown case status.', 1;
    DECLARE @DocumentPrefix nvarchar(50);
    SELECT @DocumentPrefix = p.DocumentPrefix
    FROM dbo.DemoConfiguration AS d
    INNER JOIN dbo.EmbeddingProfiles AS p ON p.ProfileId = d.ActiveProfileId
    WHERE d.ConfigurationId = 1 AND d.ActiveProfileId = @ProfileId;
    IF @DocumentPrefix IS NULL OR @Query IS NULL
        THROW 51102, 'The active embedding profile changed or is unavailable. Retry after checking embedding readiness.', 1;
    IF EXISTS
    (
        SELECT 1 FROM dbo.CaseEmbeddingInputs AS i
        LEFT JOIN dbo.CaseEmbeddings AS e ON e.CaseId = i.CaseId AND e.ProfileId = @ProfileId
        WHERE e.EmbeddingId IS NULL
           OR e.InputHash <> HASHBYTES('SHA2_256', CONCAT(@DocumentPrefix, i.InputText))
    )
        THROW 51102, 'Case embeddings are incomplete or stale. Run build-database.ps1.', 1;
    SELECT TOP (@Take) WITH APPROXIMATE c.CaseId, c.Title, c.Resolution,
        c.Topic, c.Status, s.distance AS CosineDistance
    FROM VECTOR_SEARCH(TABLE = dbo.CaseEmbeddings AS e, COLUMN = Embedding,
        SIMILAR_TO = @Query, METRIC = 'cosine') AS s
    INNER JOIN dbo.Cases AS c ON c.CaseId = e.CaseId
    WHERE e.ProfileId = @ProfileId AND (@Status IS NULL OR c.Status = @Status)
    ORDER BY s.distance;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SearchPreparedCases
    @PreparedSearchId int,
    @Take int = 5,
    @Status varchar(20) = 'Resolved'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProfileId int, @Query vector(768);
    SELECT @ProfileId = ActiveProfileId FROM dbo.DemoConfiguration WHERE ConfigurationId = 1;
    SELECT @Query = e.Embedding
    FROM dbo.QueryEmbeddings AS e
    INNER JOIN dbo.PreparedSearches AS s ON s.PreparedSearchId = e.PreparedSearchId
    INNER JOIN dbo.EmbeddingProfiles AS p ON p.ProfileId = e.ProfileId
    WHERE e.ProfileId = @ProfileId AND e.PreparedSearchId = @PreparedSearchId
      AND e.InputHash = HASHBYTES('SHA2_256', CONCAT(p.QueryPrefix, s.SearchText));
    IF @Query IS NULL
        THROW 51102, 'Prepared search is missing or stale. Regenerate its embedding.', 1;
    EXEC dbo.SearchCaseVectors @ProfileId = @ProfileId, @Query = @Query, @Take = @Take, @Status = @Status;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'CustomerServiceDeskApp') IS NULL
    CREATE ROLE CustomerServiceDeskApp AUTHORIZATION dbo;
GRANT EXECUTE ON dbo.GetCases TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.GetCase TO CustomerServiceDeskApp;
GRANT EXECUTE ON dbo.SearchPreparedCases TO CustomerServiceDeskApp;
IF DATABASE_PRINCIPAL_ID(N'CustomerServiceDeskVerifier') IS NULL
    CREATE USER CustomerServiceDeskVerifier WITHOUT LOGIN;
IF IS_ROLEMEMBER(N'CustomerServiceDeskApp', N'CustomerServiceDeskVerifier') <> 1
    ALTER ROLE CustomerServiceDeskApp ADD MEMBER CustomerServiceDeskVerifier;
