/* ============================================================================
    Performance, Demo 3: create the JSON index used by the lab-result query.

   CREATE JSON INDEX is currently an offline operation. Run this deliberately;
    it can block access to clinical.LabResultArchive while the build is active.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.json_indexes
    WHERE object_id = OBJECT_ID(N'clinical.LabResultArchive')
      AND name = N'JX_LabResultArchive_ResultJson'
)
BEGIN
    PRINT N'JX_LabResultArchive_ResultJson already exists; no change made.';
END
ELSE
BEGIN
    IF OBJECT_ID(N'clinical.LabResultArchive', N'U') IS NULL
        THROW 51013, 'Run 01-setup.sql before creating the JSON index.', 1;

    PRINT N'Creating the offline JSON index on clinical.LabResultArchive...';

    CREATE JSON INDEX JX_LabResultArchive_ResultJson
        ON clinical.LabResultArchive (ResultJson)
        FOR ('$')
        WITH (OPTIMIZE_FOR_ARRAY_SEARCH = ON);
END;
GO

SELECT
    SchemaName = OBJECT_SCHEMA_NAME(ji.object_id),
    TableName = OBJECT_NAME(ji.object_id),
    ji.name,
    ji.optimize_for_array_search
FROM sys.json_indexes AS ji
WHERE ji.object_id = OBJECT_ID(N'clinical.LabResultArchive')
ORDER BY ji.name;
GO
