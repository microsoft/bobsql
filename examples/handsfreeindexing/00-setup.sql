/*
    Caldova Hands-Free Indexing - Setup
    ===================================
    Builds an isolated workload for Caldova's cloud patient-access platform in
    an Azure SQL Database Hyperscale database. The application query intentionally
    starts without a useful nonclustered index so automatic tuning can create one.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS
(
        SELECT 1
        FROM sys.database_service_objectives
        WHERE database_id = DB_ID()
            AND edition = 'Hyperscale'
)
    THROW 50000, 'Run this demo in an Azure SQL Database Hyperscale database.', 1;
GO

ALTER DATABASE CURRENT SET AUTOMATIC_INDEX_COMPACTION = OFF;
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING
(
    FORCE_LAST_GOOD_PLAN = OFF,
    CREATE_INDEX = ON,
    DROP_INDEX = OFF
);
GO

IF SCHEMA_ID('demo') IS NULL
    EXEC ('CREATE SCHEMA demo AUTHORIZATION dbo;');
GO

DROP TABLE IF EXISTS demo.PatientAccessActivity;
GO

CREATE TABLE demo.PatientAccessActivity
(
    ActivityId bigint IDENTITY(1,1) NOT NULL,
    AppointmentNumber varchar(30) NOT NULL,
    ServiceRegionId int NOT NULL,
    ActivityAt datetime2(3) NOT NULL,
    AppointmentStatus varchar(20) NOT NULL,
    SpecialtyCode tinyint NOT NULL,
    WaitMinutes smallint NOT NULL,
    PatientInstructions varchar(7000) NOT NULL,
    OperationalContext varchar(7000) NOT NULL,
    RevisionNumber tinyint NOT NULL,
    CONSTRAINT PK_PatientAccessActivity
        PRIMARY KEY CLUSTERED (ActivityId)
);
GO

INSERT demo.PatientAccessActivity
(
    AppointmentNumber,
    ServiceRegionId,
    ActivityAt,
    AppointmentStatus,
    SpecialtyCode,
    WaitMinutes,
    PatientInstructions,
    OperationalContext,
    RevisionNumber
)
SELECT CONCAT('APT-', RIGHT(CONCAT('0000000000', series.value), 10)),
       ((series.value * 17) % 100) + 1,
       DATEADD(MINUTE, -CONVERT(int, series.value % 525600), SYSUTCDATETIME()),
       CHOOSE(((series.value / 100) % 5) + 1,
              'Requested', 'Scheduled', 'Confirmed', 'Completed', 'Cancelled'),
       ((series.value / 500) % 5) + 1,
       ((series.value / 100) * 13) % 240,
       CONCAT('Patient instructions ', series.value % 1000),
    CONCAT('Operational context ', series.value % 1000),
       0
FROM GENERATE_SERIES(1, 2000000) AS series;
GO

ALTER INDEX PK_PatientAccessActivity ON demo.PatientAccessActivity REBUILD;
GO

CREATE OR ALTER PROCEDURE demo.usp_PatientAccessDashboard
        @ServiceRegionId int,
        @FromAt datetime2(3)
AS
BEGIN
        SET NOCOUNT ON;

        DECLARE @Pass tinyint = 1;
        DECLARE @RegionalMetricRows bigint;
        DECLARE @PriorityRegionalMetricRows bigint;
        WHILE @Pass <= 18
        BEGIN
            SELECT @RegionalMetricRows = COUNT_BIG(*)
            FROM demo.PatientAccessActivity
            WHERE ServiceRegionId >= @ServiceRegionId
                AND ServiceRegionId < @ServiceRegionId + 15
                AND ActivityAt >= @FromAt;

            SET @Pass += 1;
        END;

        SELECT @PriorityRegionalMetricRows = COUNT_BIG(*)
        FROM demo.PatientAccessActivity
        WHERE ServiceRegionId >= @ServiceRegionId
            AND ServiceRegionId < @ServiceRegionId + 15
            AND ActivityAt >= @FromAt;

        SELECT AppointmentStatus,
                     SpecialtyCode,
                     COUNT_BIG(*) AS appointment_count,
                     AVG(CONVERT(bigint, WaitMinutes)) AS average_wait_minutes,
                     SUM(CONVERT(bigint, DATALENGTH(PatientInstructions))) AS instruction_bytes,
                     SUM(CONVERT(bigint, RevisionNumber)) AS revision_count
        FROM demo.PatientAccessActivity
        WHERE ServiceRegionId >= @ServiceRegionId
            AND ServiceRegionId < @ServiceRegionId + 15
            AND ActivityAt >= @FromAt
        GROUP BY AppointmentStatus, SpecialtyCode;
END;
GO

CREATE OR ALTER PROCEDURE demo.usp_ShowIndexHealth
AS
BEGIN
    SET NOCOUNT ON;

    SELECT i.name AS index_name,
           i.auto_created,
           CONVERT(decimal(6,2), ips.avg_page_space_used_in_percent) AS density_pct,
           ips.page_count,
           ips.record_count,
           CONVERT(decimal(6,2), ips.avg_fragmentation_in_percent) AS fragmentation_pct
    FROM sys.indexes AS i
    CROSS APPLY sys.dm_db_index_physical_stats
    (
        DB_ID(), i.object_id, i.index_id, NULL, 'DETAILED'
        ) AS ips
        WHERE i.object_id = OBJECT_ID('demo.PatientAccessActivity')
            AND i.index_id > 1
            AND i.is_disabled = 0
            AND EXISTS
            (
                    SELECT 1
                    FROM sys.index_columns AS ic
                    WHERE ic.object_id = i.object_id
                        AND ic.index_id = i.index_id
                        AND ic.column_id = COLUMNPROPERTY(i.object_id, 'PatientInstructions', 'ColumnId')
                        AND ic.is_included_column = 1
            )
      AND ips.index_level = 0;
END;
GO

DROP TABLE IF EXISTS demo.IndexHealthTelemetry;
DROP TABLE IF EXISTS demo.DashboardMeasurement;
DROP TABLE IF EXISTS demo.DemoState;
GO

CREATE TABLE demo.DemoState
(
    StateId tinyint NOT NULL
        CONSTRAINT PK_DemoState PRIMARY KEY
        CONSTRAINT CK_DemoState_Singleton CHECK (StateId = 1),
    Phase varchar(40) NOT NULL,
    ChangedAtUtc datetime2(3) NOT NULL
        CONSTRAINT DF_DemoState_ChangedAtUtc DEFAULT SYSUTCDATETIME()
);
GO

INSERT demo.DemoState (StateId, Phase)
VALUES (1, 'Missing Index');
GO

CREATE TABLE demo.DashboardMeasurement
(
    MeasurementId bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_DashboardMeasurement PRIMARY KEY,
    CapturedAtUtc datetime2(3) NOT NULL
        CONSTRAINT DF_DashboardMeasurement_CapturedAtUtc DEFAULT SYSUTCDATETIME(),
    DurationMs bigint NOT NULL,
    LogicalReads bigint NOT NULL
);
GO

CREATE TABLE demo.IndexHealthTelemetry
(
    SampleId bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_IndexHealthTelemetry PRIMARY KEY,
    CapturedAtUtc datetime2(3) NOT NULL
        CONSTRAINT DF_IndexHealthTelemetry_CapturedAtUtc DEFAULT SYSUTCDATETIME(),
    Phase varchar(40) NOT NULL,
    IndexName sysname NULL,
    AutoCreated bit NOT NULL,
    AutomaticIndexCompactionOn bit NOT NULL,
    DensityPercent decimal(6,2) NULL,
    PageCount bigint NULL,
    RecordCount bigint NULL,
    FragmentationPercent decimal(6,2) NULL,
    LogicalReads bigint NULL,
    DashboardDurationMs bigint NULL,
    MeasurementCapturedAtUtc datetime2(3) NULL,
    DashboardIndexName sysname NULL,
    DashboardIndexAutoCreated bit NULL
);
GO

CREATE OR ALTER PROCEDURE demo.usp_SetDemoPhase
    @Phase varchar(40)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE demo.DemoState
    SET Phase = @Phase,
        ChangedAtUtc = SYSUTCDATETIME()
    WHERE StateId = 1;
END;
GO

CREATE OR ALTER PROCEDURE demo.usp_GetDemoControlState
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Phase varchar(40);
    DECLARE @AutomaticIndexCompactionOn bit;
    DECLARE @HasQualifyingIndex bit = 0;
    DECLARE @QualifyingIndexAutoCreated bit;

    SELECT @Phase = Phase
    FROM demo.DemoState
    WHERE StateId = 1;

    SELECT @AutomaticIndexCompactionOn = is_automatic_index_compaction_on
    FROM sys.databases
    WHERE database_id = DB_ID();

    SELECT TOP (1)
           @HasQualifyingIndex = 1,
           @QualifyingIndexAutoCreated = i.auto_created
        FROM sys.indexes AS i
        WHERE i.object_id = OBJECT_ID('demo.PatientAccessActivity')
          AND i.index_id > 1
          AND i.is_disabled = 0
          AND NOT EXISTS
          (
              SELECT required.column_name
              FROM (VALUES ('ServiceRegionId'), ('ActivityAt')) AS required(column_name)
              WHERE NOT EXISTS
              (
                  SELECT 1
                  FROM sys.index_columns AS ic
                  WHERE ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
                    AND ic.column_id = COLUMNPROPERTY(i.object_id, required.column_name, 'ColumnId')
                    AND ic.is_included_column = 0
              )
          )
                    AND EXISTS
          (
              SELECT 1
              FROM sys.index_columns AS ic
              WHERE ic.object_id = i.object_id
                AND ic.index_id = i.index_id
                AND ic.column_id = COLUMNPROPERTY(i.object_id, 'PatientInstructions', 'ColumnId')
                                AND ic.is_included_column = 1
                    )
        ORDER BY i.auto_created DESC,
                         i.index_id;

        IF @Phase = 'Missing Index' AND @HasQualifyingIndex = 1
                SET @Phase = IIF(@QualifyingIndexAutoCreated = 1, 'Automatically Indexed', 'Indexed Baseline');

        IF @HasQualifyingIndex = 0
           AND @Phase IN ('Indexed Baseline', 'Automatically Indexed')
            SET @Phase = 'Missing Index';

    SELECT @Phase AS Phase,
           @AutomaticIndexCompactionOn AS AutomaticIndexCompactionOn,
           CONVERT(bit, 0) AS CanSimulateChanges,
           CONVERT(bit, IIF
           (
               @AutomaticIndexCompactionOn = 0
               AND @Phase = 'Index Bloat',
               1,
               0
           )) AS CanEnableAutomaticIndexCompaction;
END;
GO

CREATE OR ALTER PROCEDURE demo.usp_RecordDashboardMeasurement
    @durationMs bigint,
    @logicalReads bigint
AS
BEGIN
    SET NOCOUNT ON;

    INSERT demo.DashboardMeasurement (DurationMs, LogicalReads)
    VALUES (@durationMs, @logicalReads);
END;
GO

CREATE OR ALTER PROCEDURE demo.usp_CaptureIndexHealth
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

        DECLARE @QualifyingIndexName sysname;
        DECLARE @QualifyingIndexAutoCreated bit;

        SELECT TOP (1)
                 @QualifyingIndexName = i.name,
                     @QualifyingIndexAutoCreated = i.auto_created
        FROM sys.indexes AS i
        WHERE i.object_id = OBJECT_ID('demo.PatientAccessActivity')
            AND i.index_id > 1
            AND i.is_disabled = 0
            AND NOT EXISTS
    (
                SELECT required.column_name
                FROM (VALUES ('ServiceRegionId'), ('ActivityAt')) AS required(column_name)
                WHERE NOT EXISTS
                (
                        SELECT 1
                        FROM sys.index_columns AS ic
                        WHERE ic.object_id = i.object_id
                            AND ic.index_id = i.index_id
                            AND ic.column_id = COLUMNPROPERTY(i.object_id, required.column_name, 'ColumnId')
                )
    )
                AND EXISTS
    (
        SELECT 1
                FROM sys.index_columns AS ic
                WHERE ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
                    AND ic.column_id = COLUMNPROPERTY(i.object_id, 'PatientInstructions', 'ColumnId')
                    AND ic.is_included_column = 1
    )
        ORDER BY i.auto_created DESC,
                         i.index_id;

    IF @QualifyingIndexAutoCreated IS NULL
       AND EXISTS
    (
        SELECT 1
        FROM demo.DemoState
        WHERE StateId = 1
          AND Phase IN ('Indexed Baseline', 'Automatically Indexed')
    )
    BEGIN
        EXEC demo.usp_SetDemoPhase @Phase = 'Missing Index';
    END
    ELSE IF @QualifyingIndexAutoCreated IS NOT NULL
       AND EXISTS
        (
                SELECT 1
                FROM demo.DemoState
                WHERE StateId = 1
                    AND Phase = 'Missing Index'
        )
    BEGIN
                DECLARE @DetectedPhase varchar(40) = IIF
                (
                        @QualifyingIndexAutoCreated = 1,
                        'Automatically Indexed',
                        'Indexed Baseline'
                );
                EXEC demo.usp_SetDemoPhase @Phase = @DetectedPhase;
    END;

    DECLARE @IndexId int;
    DECLARE @IndexName sysname;
    DECLARE @AutoCreated bit = 0;
    DECLARE @DensityPercent decimal(6,2);
    DECLARE @PageCount bigint;
    DECLARE @RecordCount bigint;
    DECLARE @FragmentationPercent decimal(6,2);
    DECLARE @BaselineDensityPercent decimal(6,2);
    DECLARE @BaselinePageCount bigint;
    DECLARE @BloatPageCount bigint;
    DECLARE @LatestDashboardDurationMs bigint;

        SELECT TOP (1)
            @IndexId = i.index_id,
            @IndexName = i.name,
            @AutoCreated = i.auto_created
    FROM sys.indexes AS i
    WHERE i.object_id = OBJECT_ID('demo.PatientAccessActivity')
          AND i.index_id > 1
      AND i.is_disabled = 0
          AND i.name = @QualifyingIndexName;

        SELECT @PageCount = SUM(CONVERT(bigint, page_count)),
                     @RecordCount = SUM(CONVERT(bigint, record_count)),
                     @DensityPercent = CONVERT(decimal(6,2), SUM(avg_page_space_used_in_percent * page_count) / NULLIF(SUM(page_count), 0)),
                     @FragmentationPercent = CONVERT(decimal(6,2), SUM(avg_fragmentation_in_percent * page_count) / NULLIF(SUM(page_count), 0))
        FROM sys.dm_db_index_physical_stats
        (
            DB_ID(), OBJECT_ID('demo.PatientAccessActivity'), @IndexId, NULL, 'DETAILED'
        )
        WHERE index_level = 0
            AND @IndexId IS NOT NULL;

        SELECT TOP (1)
                     @BaselineDensityPercent = DensityPercent,
                     @BaselinePageCount = PageCount
        FROM demo.IndexHealthTelemetry
        WHERE Phase IN ('Indexed Baseline', 'Automatically Indexed')
            AND DensityPercent IS NOT NULL
            AND PageCount IS NOT NULL
        ORDER BY SampleId DESC;

        SELECT TOP (1)
                     @BloatPageCount = PageCount
        FROM demo.IndexHealthTelemetry
        WHERE Phase = 'Index Bloat'
            AND PageCount IS NOT NULL
        ORDER BY SampleId DESC;

        SELECT TOP (1)
                     @LatestDashboardDurationMs = DurationMs
        FROM demo.DashboardMeasurement
        ORDER BY MeasurementId DESC;

        IF EXISTS
        (
                SELECT 1
                FROM demo.DemoState
                WHERE StateId = 1
                    AND Phase = 'Compaction Running'
        )
             AND @BloatPageCount IS NOT NULL
             AND @PageCount <= @BloatPageCount * 0.20
             AND @DensityPercent >= 60
             AND @LatestDashboardDurationMs < 1000
        BEGIN
                EXEC demo.usp_SetDemoPhase @Phase = 'Compaction Complete';
        END;

    INSERT demo.IndexHealthTelemetry
    (
        Phase,
        IndexName,
        AutoCreated,
        AutomaticIndexCompactionOn,
        DensityPercent,
        PageCount,
        RecordCount,
        FragmentationPercent,
        LogicalReads,
        DashboardDurationMs,
        MeasurementCapturedAtUtc,
        DashboardIndexName,
        DashboardIndexAutoCreated
    )
    SELECT state.Phase,
           @IndexName,
           @AutoCreated,
           database_state.is_automatic_index_compaction_on,
           @DensityPercent,
           @PageCount,
           @RecordCount,
           @FragmentationPercent,
           measurement.LogicalReads,
           measurement.DurationMs,
           measurement.CapturedAtUtc,
           @QualifyingIndexName,
           @QualifyingIndexAutoCreated
    FROM demo.DemoState AS state
    CROSS JOIN
    (
        SELECT is_automatic_index_compaction_on
        FROM sys.databases
        WHERE database_id = DB_ID()
    ) AS database_state
    OUTER APPLY
    (
        SELECT TOP (1) CapturedAtUtc, LogicalReads, DurationMs
        FROM demo.DashboardMeasurement
        ORDER BY MeasurementId DESC
    ) AS measurement
    WHERE state.StateId = 1;
END;
GO

CREATE OR ALTER PROCEDURE demo.usp_GetIndexHealthTimeline
AS
BEGIN
    SET NOCOUNT ON;

    SELECT SampleId,
           CapturedAtUtc,
           Phase,
           IndexName,
           AutoCreated,
           AutomaticIndexCompactionOn,
           DensityPercent,
           PageCount,
           RecordCount,
           FragmentationPercent,
           LogicalReads,
           DashboardDurationMs,
           MeasurementCapturedAtUtc,
           DashboardIndexName,
           DashboardIndexAutoCreated
    FROM demo.IndexHealthTelemetry
    ORDER BY SampleId;
END;
GO

CREATE OR ALTER PROCEDURE demo.usp_IsAppReady
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CONVERT(bit, IIF
    (
        OBJECT_ID('demo.PatientAccessActivity', 'U') IS NOT NULL
        AND OBJECT_ID('demo.IndexHealthTelemetry', 'U') IS NOT NULL
        AND OBJECT_ID('demo.usp_PatientAccessDashboard', 'P') IS NOT NULL
        AND OBJECT_ID('demo.usp_CaptureIndexHealth', 'P') IS NOT NULL
        AND OBJECT_ID('demo.usp_GetDemoControlState', 'P') IS NOT NULL,
        1,
        0
    )) AS IsReady;
END;
GO

SELECT COUNT_BIG(*) AS activity_rows,
    MIN(ActivityAt) AS first_activity_at,
    MAX(ActivityAt) AS last_activity_at
FROM demo.PatientAccessActivity;

SELECT name,
       desired_state_desc,
       actual_state_desc
FROM sys.database_automatic_tuning_options
WHERE name IN ('FORCE_LAST_GOOD_PLAN', 'CREATE_INDEX', 'DROP_INDEX');
GO

EXEC demo.usp_CaptureIndexHealth;
GO

PRINT 'Setup complete. Run the automatic-index workload described in README.md.';
GO