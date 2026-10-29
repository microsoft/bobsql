/* Preview exact Demo 1 rows. This script changes nothing. */

SET NOCOUNT ON;

SELECT Marker = N'WG-PERF-SCALE', TableName, RowsToDelete
FROM
(
    SELECT N'clinical.Observation', COUNT_BIG(*)
    FROM clinical.Observation
    WHERE Unit LIKE N'WG-PERF-SCALE:%'

    UNION ALL

    SELECT N'clinical.MedicationOrder', COUNT_BIG(*)
    FROM clinical.MedicationOrder
    WHERE MedicationName = N'WG-PERF-SCALE:Acetaminophen'

    UNION ALL

    SELECT N'clinical.LabResult', COUNT_BIG(*)
    FROM clinical.LabResult
    WHERE JSON_VALUE(ResultJson, '$.source') = N'WG-PERF-SCALE'

    UNION ALL

    SELECT N'clinical.ClinicalNote', COUNT_BIG(*)
    FROM clinical.ClinicalNote
    WHERE NoteText LIKE N'WG-PERF-SCALE:%'
) AS counts(TableName, RowsToDelete)
ORDER BY TableName;

IF OBJECT_ID(N'clinical.ClinicalNoteEmbeddings', N'U') IS NOT NULL
BEGIN
    DECLARE @EmbeddingCount BIGINT;

    EXEC sys.sp_executesql
        N'SELECT @Count = COUNT_BIG(*)
          FROM clinical.ClinicalNoteEmbeddings AS e
          JOIN clinical.ClinicalNote AS n ON n.NoteId = e.NoteId
          WHERE n.NoteText LIKE N''WG-PERF-SCALE:%'';',
        N'@Count BIGINT OUTPUT',
        @Count = @EmbeddingCount OUTPUT;

    SELECT
        Marker = N'WG-PERF-SCALE',
        TableName = N'clinical.ClinicalNoteEmbeddings',
        RowsToDelete = @EmbeddingCount;
END;
