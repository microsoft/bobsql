/* =============================================================================
   10-row-level-security.sql  —  SESSION_CONTEXT-driven Row-Level Security
   -----------------------------------------------------------------------------
   Talk verb: SECURE IT.

   Ward General connects as ONE managed identity (trusted subsystem). That is
   great for passwordless auth, but it means every request shares a SQL principal
   — so the *app* would normally decide who sees what. We push that decision into
   the engine instead.

   On each pooled connection the app stamps the acting clinician into
   SESSION_CONTEXT (see WardGeneral.Data.ChartRepository.OpenWithContextAsync):

       EXEC sys.sp_set_session_context @key = N'ProviderId', @value = <id>, @read_only = 1;
       EXEC sys.sp_set_session_context @key = N'Role',       @value = N'Attending', @read_only = 1;

   The FILTER predicate below reads SESSION_CONTEXT and returns rows only for the
   acting attending. It is applied to clinical.Encounter, so it ALSO propagates to
   everything that reads/joins that table — clinical.vPatientChart and
   ops.vBedCensus — the chart AND the unit board shrink to "my patients".

   FAIL-OPEN design (intentional for the demo DB): when NO context is set, the
   predicate allows all rows. That keeps the RLS-off app, the diagnostics scripts,
   sqlsim, and background jobs unfiltered. A production system would flip this to
   fail-closed (deny when no context). This is called out in the book.

   sp_reset_connection (connection-pool reuse) clears SESSION_CONTEXT, so there is
   no leak between pooled requests — the app re-stamps on every open.

   Reference: Row-Level Security (Transact-SQL), CREATE SECURITY POLICY,
   sp_set_session_context — Microsoft Learn.
   ============================================================================= */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('security') IS NULL
    EXEC('CREATE SCHEMA security AUTHORIZATION dbo;');
GO

/* Drop the policy first so the schemabound predicate function can be re-created
   on every deploy (a live policy holds a schema-binding lock on the function). */
DROP SECURITY POLICY IF EXISTS security.EncounterAccessPolicy;
GO

/* -----------------------------------------------------------------------------
   Predicate: 1 = row is visible. Bound to clinical.Encounter.AttendingProviderId.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION security.fn_encounterAccess (@AttendingProviderId INT)
    RETURNS TABLE
    WITH SCHEMABINDING
AS
    RETURN
        SELECT 1 AS fn_encounterAccess_result
        WHERE
            -- Unrestricted system session: the app has not opted in (no context).
            -- RLS-off app, diagnostics, sqlsim, background jobs → see every row.
            (SESSION_CONTEXT(N'ProviderId') IS NULL
                 AND SESSION_CONTEXT(N'Role') IS NULL)
            -- Charge nurse / admin sees the whole unit.
            OR CAST(SESSION_CONTEXT(N'Role') AS NVARCHAR(30)) = N'Admin'
            -- An attending sees only encounters where they are the attending.
            OR TRY_CAST(SESSION_CONTEXT(N'ProviderId') AS INT) = @AttendingProviderId;
GO

/* -----------------------------------------------------------------------------
   Policy: FILTER hides rows from reads; BLOCK AFTER INSERT stops an app that is
   acting as provider X from writing an encounter attributed to someone else.
   ----------------------------------------------------------------------------- */
CREATE SECURITY POLICY security.EncounterAccessPolicy
    ADD FILTER PREDICATE security.fn_encounterAccess(AttendingProviderId)
        ON clinical.Encounter,
    ADD BLOCK PREDICATE  security.fn_encounterAccess(AttendingProviderId)
        ON clinical.Encounter AFTER INSERT
    WITH (STATE = ON);
GO
