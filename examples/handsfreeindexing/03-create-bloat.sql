/* Beat 3 - Create real NCI bloat without updating surviving rows. */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.databases
    WHERE database_id = DB_ID()
      AND is_automatic_index_compaction_on = 1
)
    THROW 50067, 'Automatic index compaction must be OFF before creating bloat.', 1;

DECLARE @IndexName sysname;

SELECT TOP (1) @IndexName = i.name
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID('demo.PatientAccessActivity')
  AND i.auto_created = 1
  AND i.is_disabled = 0
  AND EXISTS
  (
      SELECT 1
      FROM sys.index_columns AS ic
      WHERE ic.object_id = i.object_id
        AND ic.index_id = i.index_id
        AND ic.column_id = COLUMNPROPERTY(i.object_id, 'PatientInstructions', 'ColumnId')
        AND ic.is_included_column = 1
  );

IF @IndexName IS NULL
    THROW 50003, 'No qualifying auto-created dashboard index exists.', 1;

DECLARE @Steps TABLE
(
    StepNumber tinyint PRIMARY KEY,
    ChurnRows int NOT NULL,
    PayloadBytes int NOT NULL
);

INSERT @Steps (StepNumber, ChurnRows, PayloadBytes)
VALUES (1, 200000, 220),
       (2, 500000, 1000),
       (3, 300000, 2000),
       (4, 500000, 2000);

DECLARE @StepNumber tinyint = 1;

WHILE @StepNumber <= 4
BEGIN
    DECLARE @TotalRows int;
    DECLARE @PayloadBytes int;
    DECLARE @BatchSize int = 25000;
    DECLARE @BatchStart int = 1;
    DECLARE @Marker varchar(30) = CONCAT('BLOAT-', @StepNumber, '-');

    SELECT @TotalRows = ChurnRows,
           @PayloadBytes = PayloadBytes
    FROM @Steps
    WHERE StepNumber = @StepNumber;

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
               REPLICATE('T', @PayloadBytes),
               CONCAT('Bloat context ', series.value % 1000),
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

    SET @StepNumber += 1;
END;

IF (SELECT COUNT_BIG(*) FROM demo.PatientAccessActivity) <> 2000000
    THROW 50068, 'Bloat cleanup did not restore exactly two million base rows.', 1;

EXEC demo.usp_SetDemoPhase @Phase = 'Index Bloat';
EXEC demo.usp_ShowIndexHealth;
GO
