/* ============================================================================
   Performance, Demo 3: create the bounded JSON-index demonstration data.

   This archive belongs only to this demo. It does not depend on Demo 2 data
   growth and does not modify clinical.LabResult or any application data.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'clinical.LabResultArchive', N'U') IS NOT NULL
    THROW 51010, 'clinical.LabResultArchive already exists. Run 05-cleanup.sql before setup.', 1;
GO

CREATE TABLE clinical.LabResultArchive
(
    LabResultArchiveId BIGINT NOT NULL IDENTITY(1, 1),
    CollectedAt DATETIME2(0) NOT NULL,
    UnitCode VARCHAR(12) NOT NULL,
    ResultJson JSON NOT NULL,
    CONSTRAINT PK_LabResultArchive
        PRIMARY KEY CLUSTERED (LabResultArchiveId)
);
GO

INSERT INTO clinical.LabResultArchive
    (CollectedAt, UnitCode, ResultJson)
SELECT
    DATEADD(MINUTE, -seed.value, CONVERT(DATETIME2(0), SYSUTCDATETIME())),
    CONCAT('WARD-', seed.value),
    JSON_OBJECT(
        'specimenId': CONCAT(N'CRITICAL-', seed.value),
        'panel': N'CBC',
        'wbcValue': CONVERT(DECIMAL(4, 1), 18.0),
        'wbcUnit': N'K/uL',
        'flags': JSON_QUERY(JSON_ARRAY(N'critical', N'review'))
    )
FROM GENERATE_SERIES(1, 5) AS seed;
GO

DECLARE @Rows INT = 5000000;
DECLARE @BatchSize INT = 50000;
DECLARE @Offset INT = 0;

WHILE @Offset < @Rows
BEGIN
    ;WITH BatchRows AS
    (
        SELECT TOP (@BatchSize)
            RowNumber = CONVERT(INT, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)))
        FROM sys.all_objects AS first_set
        CROSS JOIN sys.all_objects AS second_set
    )
    INSERT INTO clinical.LabResultArchive
        (CollectedAt, UnitCode, ResultJson)
    SELECT
        DATEADD(MINUTE, -((@Offset + RowNumber) % 525600),
            CONVERT(DATETIME2(0), SYSUTCDATETIME())),
        CONCAT('WARD-', RIGHT(CONCAT('0', ((@Offset + RowNumber) % 8) + 1), 2)),
        JSON_OBJECT(
            'specimenId': CONCAT(N'ROUTINE-', @Offset + RowNumber),
            'panel': N'CBC',
            'wbcValue': CONVERT(DECIMAL(4, 1),
                4.5 + (((@Offset + RowNumber) % 65) / 10.0)),
            'wbcUnit': N'K/uL',
            'flags': JSON_QUERY(JSON_ARRAY(N'routine', N'verified'))
        )
    FROM BatchRows;

    SET @Offset += @BatchSize;
END;
GO

UPDATE STATISTICS clinical.LabResultArchive WITH FULLSCAN;
GO

SELECT ArchiveRows = COUNT_BIG(*)
FROM clinical.LabResultArchive;
GO