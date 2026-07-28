/* ============================================================================
   11-dab-adapters.sql  —  DAB (Data API Builder) boundary adapters

   WHY THIS FILE EXISTS
   --------------------------------------------------------------------------
   Data API Builder does NOT support the SQL Server 2025 native `json` or
   `vector` data types (documented, all DAB versions incl. 2.0.9):
     Learn — "Feature availability for Data API builder" > Unsupported data
     types (Microsoft SQL) lists: json, vector, xml, geography, geometry,
     hierarchyid, rowversion, sql_variant.
     https://learn.microsoft.com/azure/data-api-builder/feature-availability
   DAB introspects every stored-proc result column at startup and aborts on an
   unsupported type. The app's `clinical.GetPatientChart` / `...ByBed` return
   ELEVEN native `json` columns (IntakeJson + the JSON_ARRAYAGG/OBJECTAGG chart
   sections + the REGEXP NoteSignals), so DAB can't front them directly.

   THE ADAPTER PATTERN
   --------------------------------------------------------------------------
   The engine is one release ahead of the tooling. Rather than change the
   app-facing procs (which SHOWCASE native json all the way through), we add
   thin, DAB-ONLY wrappers that CAST each json column to nvarchar(max) — i.e.
   serialize the native type to JSON text AT THE API BOUNDARY. This is exactly
   what the TDS driver already does implicitly for older clients.

   - App path  : clinical.GetPatientChart      (native json, untouched)
   - DAB path  : clinical.GetPatientChartApi    (json -> nvarchar(max) text)

   The DAB config points its PatientChart / PatientChartByBed entities at the
   *Api procs. When DAB gains native-json support, delete this file and repoint.

   NOTE ON SHAPE: callers/agents receive the chart SECTIONS as JSON *strings*
   (e.g. "Diagnoses":"[{...}]") and parse once more — a DAB limitation, not ours.

   All data is synthetic — no real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- RLS bridge for the agent path -------------------------------------- */
/* DAB runs with set-session-context OFF and one identity, so by default the    */
/* agent path is unscoped (fail-open). This helper stamps the acting clinician   */
/* into SESSION_CONTEXT exactly like the app's DAL, so the SAME security policy  */
/* (security.EncounterAccessPolicy on clinical.Encounter) filters the agent's    */
/* chart/search results. 0/NULL = Admin (all patients). The read adapters call    */
/* this at the top (stamp) and again with NULL at the end (reset the pooled DAB  */
/* connection to Admin so scope never leaks to a later tool call).               */
/* DEMO NOTE: the acting id is supplied by the app/agent (illustrative). In       */
/* production the signed-in clinician's identity flows via OBO and DAB's          */
/* set-session-context, making this a cryptographic boundary that can't be spoofed. */
CREATE OR ALTER PROCEDURE clinical.SetAgentAccessContext
    @ActingProviderId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @ActingProviderId IS NULL OR @ActingProviderId = 0
    BEGIN
        EXEC sys.sp_set_session_context @key = N'ProviderId', @value = NULL;
        EXEC sys.sp_set_session_context @key = N'Role',       @value = N'Admin';
    END
    ELSE
    BEGIN
        EXEC sys.sp_set_session_context @key = N'ProviderId', @value = @ActingProviderId;
        EXEC sys.sp_set_session_context @key = N'Role',       @value = N'Attending';
    END
END;
GO

/* ---- DAB adapter: chart by encounter (json sections -> nvarchar(max)) --- */
CREATE OR ALTER PROCEDURE clinical.GetPatientChartApi
    @EncounterId      INT,
    @ActingProviderId INT = NULL          -- RLS: acting clinician (0/NULL = Admin/all)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC clinical.SetAgentAccessContext @ActingProviderId;

    SELECT
        EncounterId, EncounterStatus, EncounterType, AdmitTime, DischargeTime,
        CAST(IntakeJson   AS nvarchar(max)) AS IntakeJson,
        PatientId, MRN, PatientName, DateOfBirth, Sex, AgeYears,
        DepartmentId, DepartmentName, UnitId, UnitName, BedId, BedNumber,
        AttendingProviderId, AttendingProviderName, AttendingProviderRole,
        CAST(Diagnoses    AS nvarchar(max)) AS Diagnoses,
        CAST(Medications  AS nvarchar(max)) AS Medications,
        CAST(Allergies    AS nvarchar(max)) AS Allergies,
        CAST(LatestVitals AS nvarchar(max)) AS LatestVitals,
        CAST(RecentLabs   AS nvarchar(max)) AS RecentLabs,
        CAST(Symptoms     AS nvarchar(max)) AS Symptoms,
        CAST(CareTeam     AS nvarchar(max)) AS CareTeam,
        CAST(Imaging      AS nvarchar(max)) AS Imaging,
        CAST(RecentNotes  AS nvarchar(max)) AS RecentNotes,
        CAST(NoteSignals  AS nvarchar(max)) AS NoteSignals
    FROM clinical.vPatientChart
    WHERE EncounterId = @EncounterId;

    EXEC clinical.SetAgentAccessContext NULL;   -- reset pooled connection to Admin
END;
GO

/* ---- DAB adapter: chart by bed (active encounter) ---------------------- */
CREATE OR ALTER PROCEDURE clinical.GetPatientChartByBedApi
    @BedId            INT,
    @ActingProviderId INT = NULL          -- RLS: acting clinician (0/NULL = Admin/all)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC clinical.SetAgentAccessContext @ActingProviderId;

    SELECT
        EncounterId, EncounterStatus, EncounterType, AdmitTime, DischargeTime,
        CAST(IntakeJson   AS nvarchar(max)) AS IntakeJson,
        PatientId, MRN, PatientName, DateOfBirth, Sex, AgeYears,
        DepartmentId, DepartmentName, UnitId, UnitName, BedId, BedNumber,
        AttendingProviderId, AttendingProviderName, AttendingProviderRole,
        CAST(Diagnoses    AS nvarchar(max)) AS Diagnoses,
        CAST(Medications  AS nvarchar(max)) AS Medications,
        CAST(Allergies    AS nvarchar(max)) AS Allergies,
        CAST(LatestVitals AS nvarchar(max)) AS LatestVitals,
        CAST(RecentLabs   AS nvarchar(max)) AS RecentLabs,
        CAST(Symptoms     AS nvarchar(max)) AS Symptoms,
        CAST(CareTeam     AS nvarchar(max)) AS CareTeam,
        CAST(Imaging      AS nvarchar(max)) AS Imaging,
        CAST(RecentNotes  AS nvarchar(max)) AS RecentNotes,
        CAST(NoteSignals  AS nvarchar(max)) AS NoteSignals
    FROM clinical.vPatientChart
    WHERE BedId = @BedId
      AND EncounterStatus = N'Active';

    EXEC clinical.SetAgentAccessContext NULL;   -- reset pooled connection to Admin
END;
GO

/* ---- DAB adapter: admit (json param in as nvarchar -> cast to json) ---- */
/* @IntakeJson arrives as text; we serialize to native json and call the real */
/* proc. Its result set (SELECT @EncounterId AS EncounterId) flows through, so  */
/* DAB describes an INT column (no json) via the nested EXEC.                    */
CREATE OR ALTER PROCEDURE clinical.AdmitPatientApi
    @PatientId           INT,
    @DepartmentId        INT,
    @AttendingProviderId INT,
    @BedId               INT,
    @EncounterType       NVARCHAR(20)  = N'Inpatient',
    @IntakeJson          NVARCHAR(MAX) = NULL          -- text in
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @j json = @IntakeJson;                     -- serialize at the boundary
    DECLARE @NewEncounterId INT;

    EXEC clinical.AdmitPatient
        @PatientId           = @PatientId,
        @DepartmentId        = @DepartmentId,
        @AttendingProviderId = @AttendingProviderId,
        @BedId               = @BedId,
        @EncounterType       = @EncounterType,
        @IntakeJson          = @j,
        @EncounterId         = @NewEncounterId OUTPUT;
    /* The inner proc emits SELECT @EncounterId AS EncounterId — that is this     */
    /* proc's result set, so REST/GraphQL/MCP callers still get the new id.       */
END;
GO

/* ---- DAB adapter: file lab result (json param in as nvarchar) ---------- */
CREATE OR ALTER PROCEDURE clinical.FileLabResultApi
    @EncounterId INT,
    @OrderedById INT,
    @TestName    NVARCHAR(100),
    @ResultJson  NVARCHAR(MAX)  = NULL,                -- text in
    @CollectedAt DATETIME2(3)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @j json = @ResultJson;                     -- serialize at the boundary

    EXEC clinical.FileLabResult
        @EncounterId = @EncounterId,
        @OrderedById = @OrderedById,
        @TestName    = @TestName,
        @ResultJson  = @j,
        @CollectedAt = @CollectedAt;
END;
GO

/* ---- DAB adapter: search encounters with AGENT-FRIENDLY filters --------- */
/* The base clinical.SearchEncounters filters by IDs (DepartmentId, ProviderId)  */
/* and its NULL int defaults trip DAB's null->"" coercion. This adapter takes    */
/* STRING filters (default '' so DAB never coerces a null int), resolves names    */
/* internally (unit/department/provider), caps rows, and returns readable names   */
/* so an agent can answer "active encounters in ICU A" without knowing any ids.   */
CREATE OR ALTER PROCEDURE clinical.SearchEncountersApi
    @Status           NVARCHAR(20)  = NULL,   -- 'Active' | 'Discharged'
    @UnitName         NVARCHAR(100) = NULL,   -- e.g. 'ICU A' (resolved via bed -> unit)
    @DepartmentName   NVARCHAR(100) = NULL,   -- e.g. 'Cardiology'
    @ProviderName     NVARCHAR(200) = NULL,   -- attending full name (partial match)
    @Top              INT           = 200,    -- row cap so agents don't pull the whole table
    @ActingProviderId INT           = NULL    -- RLS: acting clinician (0/NULL = Admin/all)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC clinical.SetAgentAccessContext @ActingProviderId;

    /* Treat empty strings (DAB's default for an omitted param) as "no filter". */
    SET @Status         = NULLIF(LTRIM(RTRIM(@Status)), '');
    SET @UnitName       = NULLIF(LTRIM(RTRIM(@UnitName)), '');
    SET @DepartmentName = NULLIF(LTRIM(RTRIM(@DepartmentName)), '');
    SET @ProviderName   = NULLIF(LTRIM(RTRIM(@ProviderName)), '');
    IF @Top IS NULL OR @Top < 1 SET @Top = 200;

    SELECT TOP (@Top)
        e.EncounterId,
        e.PatientId,
        p.FullName                 AS PatientName,
        d.Name                     AS DepartmentName,
        u.Name                     AS UnitName,
        b.BedNumber,
        pr.FullName                AS AttendingProviderName,
        e.EncounterType,
        e.AdmitTime,
        e.DischargeTime,
        e.Status
    FROM clinical.Encounter        AS e
    JOIN clinical.Patient          AS p  ON p.PatientId    = e.PatientId
    JOIN ops.Department            AS d  ON d.DepartmentId = e.DepartmentId
    JOIN ops.Provider              AS pr ON pr.ProviderId  = e.AttendingProviderId
    LEFT JOIN ops.Bed              AS b  ON b.BedId        = e.BedId
    LEFT JOIN ops.Unit             AS u  ON u.UnitId       = b.UnitId
    WHERE (@Status         IS NULL OR e.Status = @Status)
      AND (@UnitName       IS NULL OR u.Name   = @UnitName)
      AND (@DepartmentName IS NULL OR d.Name   = @DepartmentName)
      AND (@ProviderName   IS NULL OR pr.FullName LIKE '%' + @ProviderName + '%')
    ORDER BY e.AdmitTime DESC;

    EXEC clinical.SetAgentAccessContext NULL;   -- reset pooled connection to Admin
END;
GO

PRINT '11-dab-adapters.sql complete — GetPatientChartApi, GetPatientChartByBedApi, AdmitPatientApi, FileLabResultApi, SearchEncountersApi created (DAB json boundary + agent-friendly filters).';