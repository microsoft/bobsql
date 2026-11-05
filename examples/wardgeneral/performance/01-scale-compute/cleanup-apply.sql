/* Delete exact Demo 1 marker rows as one atomic reset. */

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'clinical.ClinicalNoteEmbeddings', N'U') IS NOT NULL
    BEGIN
        EXEC sys.sp_executesql
            N'DELETE e
              FROM clinical.ClinicalNoteEmbeddings AS e
              JOIN clinical.ClinicalNote AS n ON n.NoteId = e.NoteId
              WHERE n.NoteText LIKE N''WG-PERF-SCALE:%'';';
    END;

    DELETE FROM clinical.ClinicalNote
    WHERE NoteText LIKE N'WG-PERF-SCALE:%';

    DELETE FROM clinical.LabResult
    WHERE JSON_VALUE(ResultJson, '$.source') = N'WG-PERF-SCALE';

    DELETE FROM clinical.MedicationOrder
    WHERE MedicationName = N'WG-PERF-SCALE:Acetaminophen';

    DELETE FROM clinical.Observation
    WHERE Unit LIKE N'WG-PERF-SCALE:%';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT RemainingMarkerRows =
      (SELECT COUNT_BIG(*) FROM clinical.Observation
       WHERE Unit LIKE N'WG-PERF-SCALE:%')
    + (SELECT COUNT_BIG(*) FROM clinical.MedicationOrder
       WHERE MedicationName = N'WG-PERF-SCALE:Acetaminophen')
    + (SELECT COUNT_BIG(*) FROM clinical.LabResult
       WHERE JSON_VALUE(ResultJson, '$.source') = N'WG-PERF-SCALE')
    + (SELECT COUNT_BIG(*) FROM clinical.ClinicalNote
       WHERE NoteText LIKE N'WG-PERF-SCALE:%');
