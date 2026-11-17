/* Beat 2 - Prove that automatic tuning created the dashboard index. */

SET NOCOUNT ON;
GO

DECLARE @AutoIndexId int;

SELECT TOP (1) @AutoIndexId = index_id
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID('demo.PatientAccessActivity')
  AND i.auto_created = 1
  AND i.is_disabled = 0
    AND NOT EXISTS
  (
      SELECT required.column_name
      FROM (VALUES
          ('ServiceRegionId'),
        ('ActivityAt')
      ) AS required(column_name)
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
ORDER BY i.index_id;

IF @AutoIndexId IS NULL
    THROW 50001, 'No qualifying narrow auto-created index exists yet. Keep running 01-workload.sql and check Automatic tuning history.', 1;

EXEC demo.usp_SetDemoPhase @Phase = 'Automatically Indexed';

SELECT i.name AS auto_created_index,
       i.auto_created,
       STRING_AGG(CONCAT(c.name, IIF(ic.is_included_column = 1, ' (include)', ' (key)')), ', ')
           WITHIN GROUP (ORDER BY ic.key_ordinal, ic.index_column_id) AS columns
FROM sys.indexes AS i
JOIN sys.index_columns AS ic
  ON ic.object_id = i.object_id
 AND ic.index_id = i.index_id
JOIN sys.columns AS c
  ON c.object_id = ic.object_id
 AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('demo.PatientAccessActivity')
  AND i.index_id = @AutoIndexId
GROUP BY i.name, i.auto_created;
GO

PRINT 'Automatic index verified. Refresh the app to capture paired query and physical telemetry.';
GO