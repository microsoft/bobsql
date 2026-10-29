/* Stage 1 data-plane prerequisites. Any failed requirement stops preflight. */

SET NOCOUNT ON;

IF DATABASEPROPERTYEX(DB_NAME(), 'Edition') <> N'Hyperscale'
    THROW 51001, 'Stage 1 requires an Azure SQL Hyperscale database.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_query_store_options
    WHERE actual_state_desc = N'READ_WRITE'
)
    THROW 51002, 'Query Store must be enabled and READ_WRITE.', 1;

DECLARE @MissingProcedures NVARCHAR(MAX);

SELECT @MissingProcedures = STRING_AGG(required.name, N', ')
FROM (VALUES
    (N'GetPatientChart'),
    (N'RecordVitals'),
    (N'PlaceMedicationOrder'),
    (N'FileLabResult'),
    (N'AddClinicalNote')
) AS required(name)
WHERE OBJECT_ID(N'clinical.' + required.name, N'P') IS NULL;

IF @MissingProcedures IS NOT NULL
BEGIN
    DECLARE @MissingMessage NVARCHAR(2048) =
        N'Missing required procedures: ' + @MissingProcedures;
    THROW 51004, @MissingMessage, 1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM clinical.Encounter
)
    THROW 51003, 'Stage 1 requires encounter seed data.', 1;

SELECT
    Result = N'PASS',
    DatabaseName = DB_NAME(),
    ServiceObjective = DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective'),
    QueryStoreState = N'READ_WRITE',
    RequiredProcedures = 5,
    EncounterData = N'present';
