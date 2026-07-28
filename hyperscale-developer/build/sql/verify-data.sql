/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   verify-data.sql : verify the seed landed — row counts, reserved size, and
                     automated PASS/FAIL checks that raise an error if the seed
                     is incomplete (a failed/partial seed can't pass silently).
   Run order       : after 05-seed.sql.  Set @Scale (in the checks block) to
                     match the @Scale used in 05-seed.sql (default 1.0).

   Confirms the ~10 GB dataset is in place. Pair with connect-and-verify.sql
   (which proves the tier).

   These DMVs are used informally for verification here.
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

PRINT N'-- Total reserved size (expect a little over 10 GB) -----------------';
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

DECLARE @nTables INT = (SELECT COUNT(*) FROM #rc);
INSERT @results VALUES (N'Base tables present', N'13',
    CONVERT(NVARCHAR(40), @nTables), IIF(@nTables = 13, N'PASS', N'FAIL'));

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

DECLARE @gb DECIMAL(10,2) = (SELECT CONVERT(DECIMAL(10,2), SUM(reserved_page_count) * 8.0 / 1024 / 1024) FROM sys.dm_db_partition_stats);
DECLARE @gbMin DECIMAL(10,2) = CONVERT(DECIMAL(10,2), 10.0 * @Scale);
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
    PRINT N'ALL CHECKS PASSED -- seed verified (13 tables populated, anchor + size OK).';
GO
