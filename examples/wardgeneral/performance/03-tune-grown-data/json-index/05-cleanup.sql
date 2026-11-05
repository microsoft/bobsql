/* Remove only the objects created by the Performance JSON-index demo. */

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
        DROP INDEX JX_LabResultArchive_ResultJson
                ON clinical.LabResultArchive;
END;
GO

DROP TABLE IF EXISTS clinical.LabResultArchive;
GO
