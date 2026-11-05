/* ============================================================================
   Ward General — Getting Started
   verify-data.sql : verify the seed landed — row counts, reserved size, and
                     automated PASS/FAIL checks that raise an error if the seed
                     is incomplete (a failed/partial seed can't pass silently).
   Run order       : after 05-seed.sql.  Set @Scale (in the checks block) to
                     match the @Scale used in 05-seed.sql (default 1.0).

   Confirms the ~12 GB through-line dataset is in place before later areas
   build on it. Pair with connect-and-verify.sql (which proves the tier).

   These DMVs are used informally for verification here; the full observability
   toolkit (Query Store, Extended Events, Azure Monitor, RBPEX signals) is
   taught in Observability.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'-- Row counts per table (clustered/heap base rows) ------------------';
SELECT
    s.name + N'.' + t.name                         AS TableName,
    SUM(ps.row_count)                              AS [RowCount],
    SUM(ps.reserved_page_count) * 8.0 / 1024       AS ReservedMB
FROM sys.dm_db_partition_stats ps
JOIN sys.tables  t ON t.object_id = ps.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE ps.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY ReservedMB DESC;
GO

PRINT N'-- Total reserved size (expect ~12 GB) -----------------------------';
SELECT
    SUM(reserved_page_count) * 8.0 / 1024 / 1024   AS TotalReservedGB
FROM sys.dm_db_partition_stats;
GO

/* ---------------------------------------------------------------------------
   Automated verification — PASS/FAIL. Detects a failed or partial seed and
   RAISERRORs (red in SSMS) if anything is wrong, so a bad seed can't slip by.
   Set @Scale to match the value used in 05-seed.sql (1.0 = full seed).
   Row counts come from sys.dm_db_partition_stats (fast, approximate), so the
   floors are deliberately generous to tolerate that approximation.
--------------------------------------------------------------------------- */
PRINT N'-- Verification checks (PASS/FAIL) ----------------------------------';
GO
DECLARE @Scale FLOAT = 1.0;   -- MATCH the @Scale used in 05-seed.sql

IF OBJECT_ID('tempdb..#rc') IS NOT NULL DROP TABLE #rc;
SELECT s.name AS sch, t.name AS tbl, SUM(ps.row_count) AS rows_
INTO #rc
FROM sys.dm_db_partition_stats ps
JOIN sys.tables   t ON t.object_id = ps.object_id
JOIN sys.schemas  s ON s.schema_id = t.schema_id
WHERE ps.index_id IN (0, 1) AND s.name IN (N'clinical', N'ops')
GROUP BY s.name, t.name;

DECLARE @results TABLE (CheckName NVARCHAR(60), Expected NVARCHAR(40), Actual NVARCHAR(40), Status NVARCHAR(6));

/* Base tables present. Checked BY NAME, not by counting rows in sys.tables:
   a bare count would start failing the moment a later area adds a table of
   its own (AI-Ready SQL adds clinical.ClinicalNoteEmbeddings, Agentic AI adds its
   recommendation table). This check asks only that Getting Started's 16 tables are
   all still there, so it keeps passing for the rest of the project. */
DECLARE @ch2Tables TABLE (sch NVARCHAR(20), tbl NVARCHAR(40));
INSERT @ch2Tables VALUES
    (N'ops',      N'Department'),      (N'ops',      N'Unit'),
    (N'ops',      N'Bed'),             (N'ops',      N'Provider'),
    (N'ops',      N'Appointment'),     (N'clinical', N'Patient'),
    (N'clinical', N'Encounter'),       (N'clinical', N'Diagnosis'),
    (N'clinical', N'ClinicalNote'),    (N'clinical', N'Observation'),
    (N'clinical', N'MedicationOrder'), (N'clinical', N'Allergy'),
    (N'clinical', N'LabResult'),       (N'clinical', N'Symptom'),
    (N'clinical', N'CareTeamMember'),  (N'clinical', N'ImagingOrder');

DECLARE @nTables INT = (
    SELECT COUNT(*) FROM @ch2Tables x
    WHERE EXISTS (SELECT 1 FROM #rc r WHERE r.sch = x.sch AND r.tbl = x.tbl));
INSERT @results VALUES (N'Base tables present', N'16',
    CONVERT(NVARCHAR(40), @nTables), IIF(@nTables = 16, N'PASS', N'FAIL'));

/* Per-table expected volumes (at @Scale). Fixed reference data does not scale;
   the fact tables scale with @Scale via the encounter count. ClinicalNote is
   ~1.5 notes/encounter = 60,000. */
DECLARE @expected TABLE (sch NVARCHAR(20), tbl NVARCHAR(40), expected_ BIGINT);
INSERT @expected VALUES
    (N'ops',      N'Department',      12),
    (N'ops',      N'Unit',            20),
    (N'ops',      N'Bed',             400),
    (N'ops',      N'Provider',        150),
    (N'clinical', N'Patient',         10000),
    (N'clinical', N'Allergy',         15000),
    (N'clinical', N'Encounter',       CONVERT(BIGINT, 40000     * @Scale)),
    (N'ops',      N'Appointment',     CONVERT(BIGINT, 120000    * @Scale)),
    (N'clinical', N'Diagnosis',       CONVERT(BIGINT, 80000     * @Scale)),
    (N'clinical', N'ClinicalNote',    CONVERT(BIGINT, 60000     * @Scale)),
    (N'clinical', N'MedicationOrder', CONVERT(BIGINT, 100000    * @Scale)),
    (N'clinical', N'LabResult',       CONVERT(BIGINT, 200000    * @Scale)),
    (N'clinical', N'Observation',     CONVERT(BIGINT, 108000000 * @Scale));

/* Volume check: actual >= 95% of expected. The 5% tolerance absorbs the
   approximate DMV row_count and minor per-encounter rounding. A partial load
   (e.g. a table half-seeded) FAILs instead of slipping through. */
INSERT @results
SELECT
    N'Rows: ' + e.sch + N'.' + e.tbl,
    N'>= ' + CONVERT(NVARCHAR(40), CONVERT(BIGINT, e.expected_ * 0.95)),
    CONVERT(NVARCHAR(40), ISNULL(r.rows_, 0)),
    IIF(ISNULL(r.rows_, 0) >= CONVERT(BIGINT, e.expected_ * 0.95), N'PASS', N'FAIL')
FROM @expected e
LEFT JOIN #rc r ON r.sch = e.sch AND r.tbl = e.tbl;

/* The three bedside-chart extras (05-seed.sql §14) are seeded off the ACTIVE
   encounters, not off @Scale, so their floors are expressed against the live
   active-encounter count instead of a hardcoded volume:
     Symptom        1-3 presenting complaints per active encounter
     CareTeamMember attending + 3 others per active encounter
     ImagingOrder   1-2 studies on every other active encounter
   The floors below are the conservative end of each range. */
DECLARE @activeEnc INT =
    (SELECT COUNT(*) FROM clinical.Encounter WHERE Status = N'Active');

DECLARE @chartExtras TABLE (sch NVARCHAR(20), tbl NVARCHAR(40), floor_ BIGINT);
INSERT @chartExtras VALUES
    (N'clinical', N'Symptom',        @activeEnc),
    (N'clinical', N'CareTeamMember', CONVERT(BIGINT, @activeEnc * 3)),
    (N'clinical', N'ImagingOrder',   CONVERT(BIGINT, @activeEnc / 4));

INSERT @results
SELECT
    N'Rows: ' + c.sch + N'.' + c.tbl,
    N'>= ' + CONVERT(NVARCHAR(40), c.floor_),
    CONVERT(NVARCHAR(40), ISNULL(r.rows_, 0)),
    IIF(ISNULL(r.rows_, 0) >= c.floor_, N'PASS', N'FAIL')
FROM @chartExtras c
LEFT JOIN #rc r ON r.sch = c.sch AND r.tbl = c.tbl;

DECLARE @gb DECIMAL(10,2) = (SELECT CONVERT(DECIMAL(10,2), SUM(reserved_page_count) * 8.0 / 1024 / 1024) FROM sys.dm_db_partition_stats);
DECLARE @gbMin DECIMAL(10,2) = CONVERT(DECIMAL(10,2), 11.0 * @Scale);
INSERT @results VALUES (N'Total reserved GB', N'>= ' + CONVERT(NVARCHAR(40), @gbMin),
    CONVERT(NVARCHAR(40), @gb), IIF(@gb >= @gbMin, N'PASS', N'FAIL'));

/* -----------------------------------------------------------------------
   Coherence checks — data quality, not just volume. These catch the class
   of defect that a row-count check cannot see: a bedded patient charted in
   the wrong department, or a clinical event stamped in the future. If the
   generated seed drifts, these FAIL instead of passing on counts alone.
   ----------------------------------------------------------------------- */

/* Every active, bedded encounter must be charted in the department that owns
   its bed's unit (a Cardiology bed => a Cardiology encounter). */
DECLARE @deptMismatch INT = (
    SELECT COUNT(*)
    FROM clinical.Encounter e
    JOIN ops.Bed  b ON b.BedId  = e.BedId
    JOIN ops.Unit u ON u.UnitId = b.UnitId
    WHERE e.Status = N'Active' AND u.DepartmentId <> e.DepartmentId);
INSERT @results VALUES (N'Encounter dept = bed unit dept', N'0',
    CONVERT(NVARCHAR(40), @deptMismatch), IIF(@deptMismatch = 0, N'PASS', N'FAIL'));

/* No clinical event may be stamped in the future. */
DECLARE @futureMed INT =
    (SELECT COUNT(*) FROM clinical.MedicationOrder WHERE OrderedAt > SYSUTCDATETIME());
INSERT @results VALUES (N'MedicationOrder not future', N'0',
    CONVERT(NVARCHAR(40), @futureMed), IIF(@futureMed = 0, N'PASS', N'FAIL'));

DECLARE @futureLab INT =
    (SELECT COUNT(*) FROM clinical.LabResult
      WHERE CollectedAt > SYSUTCDATETIME() OR ResultedAt > SYSUTCDATETIME());
INSERT @results VALUES (N'LabResult not future', N'0',
    CONVERT(NVARCHAR(40), @futureLab), IIF(@futureLab = 0, N'PASS', N'FAIL'));

/* EXISTS short-circuits — no need to count all 108M observation rows. */
DECLARE @futureObs INT =
    IIF(EXISTS (SELECT 1 FROM clinical.Observation WHERE RecordedAt > SYSUTCDATETIME()), 1, 0);
INSERT @results VALUES (N'Observation not future', N'none',
    IIF(@futureObs = 0, N'none', N'found'), IIF(@futureObs = 0, N'PASS', N'FAIL'));

SELECT CheckName, Expected, Actual, Status FROM @results;

IF EXISTS (SELECT 1 FROM @results WHERE Status = N'FAIL')
BEGIN
    DECLARE @msg NVARCHAR(2048) =
        N'SEED VERIFICATION FAILED: ' + (SELECT STRING_AGG(CheckName, N'; ') FROM @results WHERE Status = N'FAIL');
    RAISERROR(@msg, 16, 1);
END
ELSE
    PRINT N'ALL CHECKS PASSED -- seed verified (16 tables populated, anchor + size OK).';
GO
