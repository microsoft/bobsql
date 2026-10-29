/* =============================================================================
   row-level-security.sql — SESSION_CONTEXT-driven Row-Level Security
   -----------------------------------------------------------------------------
   Ward General connects as one managed identity. On each pooled connection the
   app stamps the acting clinician into SESSION_CONTEXT:

       EXEC sys.sp_set_session_context @key = N'ProviderId', @value = <id>, @read_only = 1;
       EXEC sys.sp_set_session_context @key = N'Role', @value = N'Attending', @read_only = 1;

   The FILTER predicate reads that context and returns rows only for the acting
   attending. Applying it to clinical.Encounter also filters the chart and unit
   board views that join to encounters.

   The demo deliberately permits sessions with no context so earlier area
   scripts and diagnostics remain usable. A production design should normally
   fail closed and provide a separately authorized administrative path.
   ============================================================================= */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('security') IS NULL
    EXEC('CREATE SCHEMA security AUTHORIZATION dbo;');
GO

DROP SECURITY POLICY IF EXISTS security.EncounterAccessPolicy;
GO

CREATE OR ALTER FUNCTION security.fn_encounterAccess (@AttendingProviderId INT)
    RETURNS TABLE
    WITH SCHEMABINDING
AS
    RETURN
        SELECT 1 AS fn_encounterAccess_result
        WHERE
            (SESSION_CONTEXT(N'ProviderId') IS NULL
                 AND SESSION_CONTEXT(N'Role') IS NULL)
            OR CAST(SESSION_CONTEXT(N'Role') AS NVARCHAR(30)) = N'Admin'
            OR TRY_CAST(SESSION_CONTEXT(N'ProviderId') AS INT) = @AttendingProviderId;
GO

CREATE SECURITY POLICY security.EncounterAccessPolicy
    ADD FILTER PREDICATE security.fn_encounterAccess(AttendingProviderId)
        ON clinical.Encounter,
    ADD BLOCK PREDICATE security.fn_encounterAccess(AttendingProviderId)
        ON clinical.Encounter AFTER INSERT
    WITH (STATE = ON);
GO