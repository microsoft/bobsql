/* ============================================================================
    12-handoff-candidates.sql  —  the roster the agent ranks

   WHY THIS PROCEDURE EXISTS
   --------------------------------------------------------------------------
   search_encounters answers "who is admitted". It says nothing about what has
   CHANGED, and change is the whole content of a shift handoff. Without this
   procedure the agent has two bad options: rank on admit time, which is
   meaningless, or call get_patient_chart once per candidate and reconstruct the
   answer itself — ten round trips and ten charts of context to compute what one
   query already knows.

   That is the lesson worth taking from this file. An agent that fans out to N
   tool calls to rebuild a GROUP BY is doing the database's job, badly. Push the
   set-based work into the engine and hand the model a small, already-joined
   result.

   WHAT IT DELIBERATELY DOES NOT DO
   --------------------------------------------------------------------------
   It does not rank. There is no score column and no ORDER BY that claims to be
   a priority. The database GATHERS evidence; the model WEIGHS it. Encoding
   "a rising respiratory rate outranks a pending troponin" in T-SQL would move
   clinical judgment into a CASE expression and make the agent a formatter.
   The rows come back most-recently-touched first purely so the output is
   deterministic.

   A KNOWN LIMITATION, STATED RATHER THAN PAPERED OVER
   --------------------------------------------------------------------------
   clinical.Diagnosis has no timestamp column — Getting Started did not give it one.
   So "a diagnosis added in the last twelve hours" cannot be computed here.
   LatestDiagnosis uses DiagnosisId order as a proxy for insertion order, which
   is true of an IDENTITY column but is not the same as a recorded time. Every
   other signal below is genuinely windowed.

    Agentic AI has no authentication or row-level authorization, so this procedure
    returns active patients across the synthetic hospital. Security owns adding
    authenticated identity and Row-Level Security.

   RERUNNABLE. Safe to execute more than once.
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

CREATE OR ALTER PROCEDURE clinical.GetHandoffCandidates
    @SinceHours       INT = 12,     -- one shift
    @Top              INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @SinceHours IS NULL OR @SinceHours <= 0 SET @SinceHours = 12;
    IF @Top        IS NULL OR @Top        <= 0 SET @Top        = 10;

    DECLARE @since DATETIME2(3) = DATEADD(HOUR, -@SinceHours, SYSUTCDATETIME());

    SELECT TOP (@Top)
        e.EncounterId,
        e.PatientId,
        p.FullName                                            AS PatientName,
        DATEDIFF(YEAR, p.DateOfBirth, SYSUTCDATETIME())       AS AgeYears,
        p.Sex,
        u.Name                                                AS UnitName,
        b.BedNumber,
        e.EncounterType,
        e.AdmitTime,
        DATEDIFF(HOUR, e.AdmitTime, SYSUTCDATETIME())         AS HoursSinceAdmit,

        /* What is wrong with them */
        ISNULL(dx.DiagnosisCount, 0)                          AS DiagnosisCount,
        dxl.LatestDiagnosis,
        ISNULL(al.SevereAllergyCount, 0)                      AS SevereAllergyCount,

        /* What changed this shift */
        ISNULL(med.NewMedCount, 0)                            AS MedsStartedInWindow,
        medl.LatestMedication,
        ISNULL(nte.NotesInWindow, 0)                          AS NotesInWindow,
        nte.LatestNoteAt,

        /* What the next shift will have to chase */
        ISNULL(lab.PendingLabCount, 0)                        AS PendingLabCount,
        labl.OldestPendingTest,
        labl.OldestPendingSince,

        /* Where the numbers are going: latest value per vital, and the first
           value inside the window, so direction of travel is visible without a
           second call. */
        vit.Vitals
    FROM clinical.Encounter AS e
        INNER JOIN clinical.Patient AS p ON p.PatientId = e.PatientId
        LEFT  JOIN ops.Bed          AS b ON b.BedId     = e.BedId
        LEFT  JOIN ops.Unit         AS u ON u.UnitId    = b.UnitId

        OUTER APPLY (
            SELECT COUNT(*)          AS DiagnosisCount,
                   MAX(d.DiagnosisId) AS LatestDiagnosisId
            FROM clinical.Diagnosis AS d
            WHERE d.EncounterId = e.EncounterId
        ) AS dx
        OUTER APPLY (
            SELECT d.Description AS LatestDiagnosis
            FROM clinical.Diagnosis AS d
            WHERE d.DiagnosisId = dx.LatestDiagnosisId
        ) AS dxl

        OUTER APPLY (
            SELECT COUNT(*) AS SevereAllergyCount
            FROM clinical.Allergy AS a
            WHERE a.PatientId = e.PatientId
              AND a.Severity  = N'Severe'
        ) AS al

        OUTER APPLY (
            SELECT COUNT(*)       AS NewMedCount,
                   MAX(m.OrderedAt) AS LatestMedAt
            FROM clinical.MedicationOrder AS m
            WHERE m.EncounterId = e.EncounterId
              AND m.OrderedAt  >= @since
        ) AS med
        OUTER APPLY (
            SELECT TOP (1)
                   m.MedicationName + ISNULL(N' ' + m.Dose, N'') AS LatestMedication
            FROM clinical.MedicationOrder AS m
            WHERE m.EncounterId = e.EncounterId
              AND m.OrderedAt  >= @since
            ORDER BY m.OrderedAt DESC
        ) AS medl

        OUTER APPLY (
            SELECT COUNT(CASE WHEN n.CreatedAt >= @since THEN 1 END) AS NotesInWindow,
                   MAX(n.CreatedAt)                                  AS LatestNoteAt
            FROM clinical.ClinicalNote AS n
            WHERE n.EncounterId = e.EncounterId
        ) AS nte

        OUTER APPLY (
            SELECT COUNT(*) AS PendingLabCount
            FROM clinical.LabResult AS l
            WHERE l.EncounterId = e.EncounterId
              AND l.Status IN (N'Ordered', N'Collected')
        ) AS lab
        OUTER APPLY (
            SELECT TOP (1)
                   l.TestName    AS OldestPendingTest,
                   l.CollectedAt AS OldestPendingSince
            FROM clinical.LabResult AS l
            WHERE l.EncounterId = e.EncounterId
              AND l.Status IN (N'Ordered', N'Collected')
            ORDER BY l.CollectedAt ASC
        ) AS labl

        OUTER APPLY (
            SELECT (
                SELECT
                    t.ObservationType  AS [type],
                    t.Latest           AS [latest],
                    t.Unit             AS [unit],
                    t.LatestAt         AS [at],
                    t.EarlierInWindow  AS [earlier]
                FROM (
                    SELECT
                        o.ObservationType,
                        MAX(o.Unit)                                                  AS Unit,
                        MAX(CASE WHEN o.NewestFirst = 1 THEN o.ValueNumeric END)     AS Latest,
                        MAX(CASE WHEN o.NewestFirst = 1 THEN o.RecordedAt   END)     AS LatestAt,
                        MAX(CASE WHEN o.OldestFirst = 1 THEN o.ValueNumeric END)     AS EarlierInWindow
                    FROM (
                        SELECT
                            o.ObservationType, o.ValueNumeric, o.Unit, o.RecordedAt,
                            ROW_NUMBER() OVER (PARTITION BY o.ObservationType
                                               ORDER BY o.RecordedAt DESC) AS NewestFirst,
                            ROW_NUMBER() OVER (PARTITION BY o.ObservationType
                                               ORDER BY o.RecordedAt ASC)  AS OldestFirst
                        FROM clinical.Observation AS o
                        WHERE o.EncounterId = e.EncounterId
                          AND o.RecordedAt >= @since
                    ) AS o
                    GROUP BY o.ObservationType
                ) AS t
                FOR JSON PATH
            ) AS Vitals
        ) AS vit
        WHERE e.Status = N'Active'
    /* Recency, not priority — see the header. The model does the ranking. */
    ORDER BY COALESCE(nte.LatestNoteAt, med.LatestMedAt, e.AdmitTime) DESC;

END;
GO
