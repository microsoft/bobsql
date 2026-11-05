/* ============================================================================
    Performance, Demo 3: JSON predicate before the JSON index.

    The script returns actual Showplan XML automatically. The predicate finds
    the deliberately rare critical lab-result flags in the bounded demo archive.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS XML ON;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.json_indexes
    WHERE object_id = OBJECT_ID(N'clinical.LabResultArchive')
      AND name = N'JX_LabResultArchive_ResultJson'
)
    THROW 51011, 'The Performance JSON index already exists. Run 05-cleanup.sql before repeating the demo.', 1;
GO

IF OBJECT_ID(N'clinical.LabResultArchive', N'U') IS NULL
    THROW 51012, 'Run 01-setup.sql before capturing the baseline.', 1;
GO

SELECT
    SpecimenId = JSON_VALUE(ResultJson, '$.specimenId'),
    WbcValue = JSON_VALUE(ResultJson, '$.wbcValue' RETURNING DECIMAL(4, 1)),
    Flags = JSON_QUERY(ResultJson, '$.flags')
FROM clinical.LabResultArchive
WHERE JSON_CONTAINS(ResultJson, N'critical', '$.flags[*]') = 1
OPTION (MAXDOP 1);
GO

SET STATISTICS XML OFF;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
