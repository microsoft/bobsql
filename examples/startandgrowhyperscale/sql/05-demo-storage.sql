IF DB_NAME() NOT IN (N'caldova-scheduling', N'northbrook-scheduling', N'ridgeview-scheduling')
    THROW 50000, 'Connect to an approved Caldova provider database.', 1;

IF SCHEMA_ID(N'demo') IS NULL EXEC(N'CREATE SCHEMA demo AUTHORIZATION dbo;');
IF OBJECT_ID(N'demo.StoragePayload', N'U') IS NULL
BEGIN
    CREATE TABLE demo.StoragePayload (
        RowId bigint IDENTITY(1,1) NOT NULL,
        Payload binary(7800) NOT NULL,
        CONSTRAINT PK_DemoStoragePayload PRIMARY KEY CLUSTERED (RowId)
            WITH (DATA_COMPRESSION = NONE)
    );
END;
IF COL_LENGTH(N'demo.StoragePayload', N'Payload') <> 7800
    OR COLUMNPROPERTY(OBJECT_ID(N'demo.StoragePayload'), N'RowId', 'IsIdentity') <> 1
    OR EXISTS (SELECT 1 FROM sys.partitions
        WHERE object_id = OBJECT_ID(N'demo.StoragePayload') AND data_compression <> 0)
    THROW 50001, 'Existing demo storage table does not match the uncompressed payload schema.', 1;
GO
CREATE OR ALTER VIEW demo.StorageSize
AS
    SELECT SUM(CONVERT(bigint, FILEPROPERTY(name, 'SpaceUsed'))) * CONVERT(bigint,8192) AS UsedBytes,
        SUM(CONVERT(bigint,size)) * CONVERT(bigint,8192) AS AllocatedBytes,
        COUNT(*) AS DataFiles,
        SUM(CASE WHEN FILEPROPERTY(name, 'SpaceUsed') IS NULL THEN 1 ELSE 0 END) AS MissingFiles
    FROM sys.database_files WHERE type = 0;
GO
CREATE OR ALTER PROCEDURE demo.FillStorageBatch
    @TargetBytes bigint,
    @MaxRows int = 4096
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @maximum bigint = CASE DB_NAME()
        WHEN N'caldova-scheduling' THEN CONVERT(bigint,22) * 1073741824
        WHEN N'northbrook-scheduling' THEN CONVERT(bigint,12) * 1073741824
        WHEN N'ridgeview-scheduling' THEN CONVERT(bigint,15) * 1073741824 END;
    IF @maximum IS NULL OR @TargetBytes IS NULL OR @MaxRows IS NULL
        OR @TargetBytes <= 0 OR @TargetBytes > @maximum OR @MaxRows NOT BETWEEN 1 AND 4096
        THROW 50002, 'Storage target or batch is outside the approved provider limits.', 1;
    IF @@TRANCOUNT <> 0
        THROW 50003, 'Run the storage batch without an outer transaction.', 1;
    BEGIN TRANSACTION;
    DECLARE @lock int;
    EXEC @lock = sys.sp_getapplock @Resource=N'Caldova.DemoStorageFill',
        @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=0;
    IF @lock < 0
        THROW 50004, 'Another writer is filling this database. No batch was inserted.', 1;
    DECLARE @used bigint, @missing int, @files int;
    SELECT @used=UsedBytes, @missing=MissingFiles, @files=DataFiles FROM demo.StorageSize;
    IF @used IS NULL OR @files = 0 OR @missing <> 0
        THROW 50005, 'SQL did not report used space for every data file.', 1;
    DECLARE @remaining bigint = CEILING((@TargetBytes - @used) / 8192.0);
    DECLARE @rows int = CASE WHEN @remaining <= 0 THEN 0
        WHEN @remaining > @MaxRows THEN @MaxRows ELSE CONVERT(int,@remaining) END;
    DECLARE @inserted int = 0;
    IF @rows > 0
    BEGIN
        DECLARE @payload binary(7800) = CRYPT_GEN_RANDOM(7800);
        INSERT demo.StoragePayload (Payload)
            SELECT TOP (@rows) @payload FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;
        SET @inserted = @@ROWCOUNT;
        IF @inserted = 0 THROW 50006, 'The storage insert produced no rows.', 1;
    END;
    COMMIT TRANSACTION;
    SELECT @inserted;
END;
GO
-- $(AppName) is the App Service name; the app substitutes it from private configuration before running this file.
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'$(AppName)')
BEGIN
    GRANT SELECT ON OBJECT::demo.StorageSize TO [$(AppName)];
    GRANT EXECUTE ON OBJECT::demo.FillStorageBatch TO [$(AppName)];
END;
GO
