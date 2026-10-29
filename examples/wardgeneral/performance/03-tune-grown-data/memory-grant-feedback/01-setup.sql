/* ============================================================================
    Performance, Demo 3: prepare a memory grant feedback demonstration.

   The table represents archived nursing shift reports. It belongs only to this
    demo and does not depend on Demo 2 growth.

    UnitCode, AcuityCode, and ShiftType are strongly correlated. Current
    single-column statistics describe each distribution accurately but cannot
    fully describe the cross-column correlation. The report query combines all
    three predicates and sorts the matching wide ICU reports.
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

IF (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID()) < 160
    THROW 51020, 'This feedback experiment requires database compatibility level 160 or higher.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_query_store_options
    WHERE actual_state_desc = N'READ_WRITE'
)
    THROW 51021, 'Query Store must be enabled and READ_WRITE for persisted and percentile memory grant feedback.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.database_scoped_configurations
    WHERE name = N'ROW_MODE_MEMORY_GRANT_FEEDBACK'
      AND value = 0
)
    THROW 51022, 'ROW_MODE_MEMORY_GRANT_FEEDBACK must be ON.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.database_scoped_configurations
    WHERE name IN
    (
        N'MEMORY_GRANT_FEEDBACK_PERSISTENCE',
        N'MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT'
    )
      AND value = 0
)
    THROW 51023, 'Memory grant feedback persistence and percentile grant must be ON.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.database_scoped_configurations
    WHERE name = N'CE_FEEDBACK'
      AND value = 0
)
    THROW 51026, 'CE_FEEDBACK must be ON so the experiment can observe both feedback features.', 1;

IF OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback', N'P') IS NOT NULL
   OR OBJECT_ID(N'clinical.ShiftReportArchive', N'U') IS NOT NULL
    THROW 51024, 'Demo objects already exist. Run 03-cleanup.sql before setup.', 1;
GO

CREATE TABLE clinical.ShiftReportArchive
(
    ShiftReportId BIGINT NOT NULL IDENTITY(1, 1),
    ShiftStartedAt DATETIME2(0) NOT NULL,
    UnitCode VARCHAR(12) NOT NULL,
    AcuityCode VARCHAR(12) NOT NULL,
    ShiftType VARCHAR(12) NOT NULL,
    ReportText NVARCHAR(4000) NOT NULL,
    CONSTRAINT PK_ShiftReportArchive
        PRIMARY KEY CLUSTERED (ShiftReportId)
);
GO

INSERT INTO clinical.ShiftReportArchive
    (ShiftStartedAt, UnitCode, AcuityCode, ShiftType, ReportText)
SELECT
    DATEADD(HOUR, -8 * (gs.value % 1000), SYSUTCDATETIME()),
    CASE WHEN gs.value % 100 = 0 THEN 'ICU'
         ELSE CONCAT('WARD-', gs.value % 10) END,
    CASE WHEN gs.value % 100 = 0 THEN 'Critical'
         ELSE 'Routine' END,
    CASE WHEN gs.value % 100 = 0 THEN 'Night'
         ELSE 'Day' END,
    CASE
        WHEN gs.value % 100 = 0 THEN CONCAT(
            N'ICU night-shift handoff: ',
            REPLICATE(N'Patient status reviewed; medications reconciled; pending labs, respiratory support, hemodynamic trends, and follow-up actions documented. ', 24),
            N'Report ', gs.value)
        ELSE CONCAT(N'Routine ward handoff. Report ', gs.value)
    END
FROM GENERATE_SERIES(1, 5000000) AS gs;
GO

CREATE STATISTICS ST_ShiftReportArchive_UnitCode
    ON clinical.ShiftReportArchive (UnitCode)
    WITH FULLSCAN;
GO

CREATE STATISTICS ST_ShiftReportArchive_AcuityCode
    ON clinical.ShiftReportArchive (AcuityCode)
    WITH FULLSCAN;
GO

CREATE STATISTICS ST_ShiftReportArchive_ShiftType
    ON clinical.ShiftReportArchive (ShiftType)
    WITH FULLSCAN;
GO

CREATE INDEX IX_ShiftReportArchive_UnitCode
    ON clinical.ShiftReportArchive (UnitCode)
    INCLUDE (AcuityCode, ShiftType, ReportText);
GO

CREATE PROCEDURE clinical.DemonstrateMemoryGrantFeedback
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ReportChecksum = CHECKSUM_AGG(CHECKSUM(SequenceNumber, ReportText))
    FROM
    (
        SELECT
            ReportText,
            SequenceNumber = ROW_NUMBER() OVER (ORDER BY ReportText)
        FROM clinical.ShiftReportArchive
        WHERE UnitCode = 'ICU'
          AND AcuityCode = 'Critical'
          AND ShiftType = 'Night'
    ) AS ordered_reports;
END;
GO

SELECT
    Result = N'READY',
    CompatibilityLevel =
        (SELECT compatibility_level
         FROM sys.databases
         WHERE database_id = DB_ID()),
    ReportRows = COUNT_BIG(*),
    IcuCriticalNightRows = SUM
    (
        CASE
            WHEN UnitCode = 'ICU'
             AND AcuityCode = 'Critical'
             AND ShiftType = 'Night'
                THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ),
    StatisticsAreCurrent = IIF
    (
        STATS_DATE(OBJECT_ID(N'clinical.ShiftReportArchive'),
            (SELECT stats_id
             FROM sys.stats
             WHERE object_id = OBJECT_ID(N'clinical.ShiftReportArchive')
               AND name = N'ST_ShiftReportArchive_ShiftType')) IS NOT NULL,
        1,
        0
    )
FROM clinical.ShiftReportArchive;
GO