/* Beat 4 - Enable AIC and make sparse ranges eligible without updating base rows. */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('demo.PatientAccessActivity')
      AND auto_created = 1
      AND is_disabled = 0
)
    THROW 50069, 'No auto-created dashboard index exists.', 1;

ALTER DATABASE CURRENT SET AUTOMATIC_INDEX_COMPACTION = ON;
EXEC demo.usp_SetDemoPhase @Phase = 'Compaction Running';
GO

DECLARE @Cycle tinyint = 1;

WHILE @Cycle <= 3
BEGIN
    DECLARE @TotalRows int = 200000;
    DECLARE @BatchSize int = 25000;
    DECLARE @BatchStart int = 1;
    DECLARE @Marker varchar(30) = CONCAT('AIC-', @Cycle, '-');

    WHILE @BatchStart <= @TotalRows
    BEGIN
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
        SELECT CONCAT(@Marker, RIGHT(CONCAT('0000000000', series.value), 10)),
               42 + ((series.value - 1) % 29),
               DATEADD(MINUTE, -CONVERT(int, (series.value * 13) % 525600), SYSUTCDATETIME()),
               CHOOSE(((series.value - 1) % 5) + 1,
                      'Requested', 'Scheduled', 'Confirmed', 'Completed', 'Cancelled'),
               ((series.value - 1) % 5) + 1,
               (series.value * 7) % 240,
               REPLICATE('E', 220),
               CONCAT('AIC eligibility context ', series.value % 1000),
               0
        FROM GENERATE_SERIES
        (
            @BatchStart,
            IIF(@BatchStart + @BatchSize - 1 > @TotalRows,
                @TotalRows,
                @BatchStart + @BatchSize - 1)
        ) AS series;

        SET @BatchStart += @BatchSize;
    END;

    WHILE EXISTS
    (
        SELECT 1
        FROM demo.PatientAccessActivity
        WHERE AppointmentNumber LIKE @Marker + '%'
    )
    BEGIN
        DELETE TOP (25000)
        FROM demo.PatientAccessActivity
        WHERE AppointmentNumber LIKE @Marker + '%';
    END;

    SET @Cycle += 1;
END;

IF (SELECT COUNT_BIG(*) FROM demo.PatientAccessActivity) <> 2000000
    THROW 50070, 'AIC eligibility cleanup did not restore exactly two million base rows.', 1;

SELECT name AS database_name,
       is_automatic_index_compaction_on
FROM sys.databases
WHERE database_id = DB_ID();

EXEC demo.usp_ShowIndexHealth;
GO
