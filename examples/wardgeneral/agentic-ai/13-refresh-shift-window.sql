/* ============================================================================
    13-refresh-shift-window.sql  —  re-anchor the shift window to "now"

   WHY THIS SCRIPT EXISTS
   --------------------------------------------------------------------------
   Getting Started's seed is written relative to the moment it runs: active admissions
   land 1-95 hours before SYSUTCDATETIME(), and every vital, note, medication
   and lab hangs off that. It is correct on the day it is seeded and decays from
   there. A reader who seeds in Getting Started and reaches Agentic AI a month later has
   a database where the newest clinical activity is weeks old.

   That breaks exactly one thing, but it is the thing this area is about.
   clinical.GetHandoffCandidates windows its signals to @SinceHours (12 by
   default - one shift). With no activity inside the window every signal comes
   back zero, the roster is empty, and the agent correctly reports that nobody
   needs a handoff. Nothing is broken; there is simply nothing to hand off.

   The fix is NOT to widen the window. "One shift" is the meaning of the tool,
   and stretching it to make a demo look alive would move the problem into the
   contract. Instead this script moves the DATA to where the reader is standing:
   it shifts the whole activity block forward as one rigid body, so relative
   spacing, trends and orderings are preserved exactly and only the anchor
   changes.

   WHAT IT SHIFTS, AND WHAT IT DELIBERATELY DOES NOT
   --------------------------------------------------------------------------
   Shifted, for ACTIVE encounters only: Encounter.AdmitTime, Observation,
   MedicationOrder, ClinicalNote, LabResult (BOTH CollectedAt and ResultedAt -
   moving one without the other would date a result before its own collection),
   Symptom and ImagingOrder.

   NOT shifted:
     - Discharged encounters. They are the past, and their ~60,000 notes are the
       historical corpus search_clinical_context retrieves from. Freshening them
       would make "historical precedent" mean nothing.
     - clinical.Allergy. Patient-scoped and long-standing, not shift activity.
     - clinical.Patient.CreatedAt and DateOfBirth. Ages are derived from
       DateOfBirth and are supposed to drift.

   Note embeddings are keyed on NoteId, not on a date, so moving note timestamps
   does not invalidate the vector index built in AI-Ready SQL. Nothing needs
   re-embedding after this runs.

   THE ANCHOR IS 15 MINUTES IN THE PAST, ON PURPOSE
   --------------------------------------------------------------------------
   Getting Started's verify-data.sql asserts that no medication, collection or result
   is dated in the future. Anchoring the newest row at SYSUTCDATETIME() - 15
   minutes keeps every shifted row in the past and that check passing. "Shift
   forward" is one arithmetic slip away from failing a Getting Started test.

   PENDING LABS
   --------------------------------------------------------------------------
   Part 2 fixes a gap that has nothing to do with dates. PendingLabCount counts
   labs in status 'Ordered' or 'Collected' and is NOT windowed - yet every lab
   the seed writes is already 'Resulted'. So that signal, and the "how long has
   the oldest been outstanding" that the tool description advertises, could never
   fire on any reader's machine. Part 2 gives a deterministic 40% of active
   encounters one genuinely outstanding lab.

   VITALS THAT ACTUALLY TREND
   --------------------------------------------------------------------------
   Part 3 fixes a third defect, and it is the one that most affects what the
   agent says. Getting Started generates vitals as a counter: each reading is the
   previous one plus one, wrapping back to the bottom of the band at the top.
   A heart-rate series reads 117, 118, 119, 100, 101 - a ramp with a cliff in it.

   That matters because the handoff tool reports each vital as `latest` against
   `earlier`, the first reading in the same 12-hour window, and the agent is
   instructed to quote that pair as its evidence. Against a counter, the pair is
   an artifact of where the window happens to start: "heart rate 128, up from
   121" is just the ramp advancing. Worse, when the wrap falls inside the window
   the pair inverts - `earlier` 119 against `latest` 100 - and a patient appears
   to have dramatically improved when nothing happened at all.

   The agent is not wrong when it says this. It is quoting the row it was given,
   faithfully, which is exactly what it was asked to do. The data is what is
   wrong, so the data is what this fixes.

   Part 3 rewrites the vitals inside the window as a straight line from a
   per-encounter baseline, with a small non-monotone jitter so the series is not
   suspiciously perfect. Encounters are assigned a course by EncounterId, so two
   readers see the same ward:

       (EncounterId / 5) % 5 = 0    deteriorating - drifts away from baseline
       (EncounterId / 5) % 5 = 1    improving     - starts abnormal, returns to it
       otherwise                    stable        - holds baseline, jitter only

   The divisor differs from the one Part 2 uses on purpose. Part 2 selects its
   outstanding labs with EncounterId % 5, and reusing that here would have made
   every deteriorating patient also the patient with a pending lab - two signals
   that always agree teach the reader nothing about weighing evidence.

   Twenty percent deteriorating is high for a real hospital and low enough to
   still be a ward. It matters because clinical.GetHandoffCandidates deliberately
   does NOT rank - it returns the ten most recently active encounters and leaves
   the judgement to the model. If only a couple of patients in the whole hospital
   were trending, the roster would usually contain none of them and the agent
   would have nothing to reason about.

   Values are absolute, not incremental, so rerunning recomputes the same line
   rather than compounding a drift.

   RERUNNABLE, and cheap on a rerun. Safe to execute more than once - the shift
   recomputes its delta from the current data and does nothing when the window is
   already fresh, the lab insert skips any encounter that already has one
   outstanding, and the vitals rewrite is a pure function of the encounter and the
   reading's position in the window, so it updates only the rows whose value would
   actually change. A second run in the same window typically reports zero.
   All data is synthetic - no real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

SET XACT_ABORT ON;
GO

/* ---- Part 1: shift the active-encounter activity block forward ----------- */

SET NOCOUNT ON;

DECLARE @anchor DATETIME2(3) = DATEADD(MINUTE, -15, SYSUTCDATETIME());
DECLARE @newest DATETIME2(3);
DECLARE @delta  INT;

SELECT @newest = MAX(x.At)
FROM (
    SELECT MAX(o.RecordedAt) AS At
        FROM clinical.Observation AS o
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = o.EncounterId AND e.Status = N'Active'
    UNION ALL
    SELECT MAX(m.OrderedAt)
        FROM clinical.MedicationOrder AS m
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = m.EncounterId AND e.Status = N'Active'
    UNION ALL
    SELECT MAX(n.CreatedAt)
        FROM clinical.ClinicalNote AS n
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = n.EncounterId AND e.Status = N'Active'
    UNION ALL
    SELECT MAX(l.CollectedAt)
        FROM clinical.LabResult AS l
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = l.EncounterId AND e.Status = N'Active'
) AS x;

/* Minutes, not seconds: a reader returning a year later is 525,600 minutes out,
   which is comfortably inside INT. The same gap in seconds is not comfortable. */
SET @delta = DATEDIFF(MINUTE, @newest, @anchor);

IF @newest IS NULL
BEGIN
    RAISERROR('No active-encounter activity found. Run the Getting Started seed first.', 16, 1);
END
ELSE IF @delta <= 0
BEGIN
    PRINT CONCAT('Window already fresh - newest activity ',
                 DATEDIFF(MINUTE, @newest, SYSUTCDATETIME()),
                 ' minutes old. No shift applied.');
END
ELSE
BEGIN
    PRINT CONCAT('Shifting active-encounter activity forward by ', @delta,
                 ' minutes (', @delta / 60, ' hours). Newest was ', CONVERT(NVARCHAR(23), @newest),
                 ', will become ', CONVERT(NVARCHAR(23), @anchor), '.');

    /* One transaction: a partial shift would leave the tables inconsistent with
       each other, and a rerun would recompute a delta of ~0 from the already
       shifted rows and never repair the ones that were missed. */
    BEGIN TRANSACTION;

        UPDATE e
            SET e.AdmitTime = DATEADD(MINUTE, @delta, e.AdmitTime)
        FROM clinical.Encounter AS e
        WHERE e.Status = N'Active';

        UPDATE o
            SET o.RecordedAt = DATEADD(MINUTE, @delta, o.RecordedAt)
        FROM clinical.Observation AS o
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = o.EncounterId AND e.Status = N'Active';

        UPDATE m
            SET m.OrderedAt = DATEADD(MINUTE, @delta, m.OrderedAt)
        FROM clinical.MedicationOrder AS m
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = m.EncounterId AND e.Status = N'Active';

        UPDATE n
            SET n.CreatedAt = DATEADD(MINUTE, @delta, n.CreatedAt)
        FROM clinical.ClinicalNote AS n
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = n.EncounterId AND e.Status = N'Active';

        UPDATE l
            SET l.CollectedAt = DATEADD(MINUTE, @delta, l.CollectedAt),
                l.ResultedAt  = DATEADD(MINUTE, @delta, l.ResultedAt)
        FROM clinical.LabResult AS l
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = l.EncounterId AND e.Status = N'Active';

        UPDATE s
            SET s.NotedAt = DATEADD(MINUTE, @delta, s.NotedAt)
        FROM clinical.Symptom AS s
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = s.EncounterId AND e.Status = N'Active';

        UPDATE i
            SET i.OrderedAt  = DATEADD(MINUTE, @delta, i.OrderedAt),
                i.ResultedAt = DATEADD(MINUTE, @delta, i.ResultedAt)
        FROM clinical.ImagingOrder AS i
        INNER JOIN clinical.Encounter AS e
            ON e.EncounterId = i.EncounterId AND e.Status = N'Active';

    COMMIT TRANSACTION;

    PRINT 'Shift complete.';
END;
GO

/* ---- Part 2: give some patients a genuinely outstanding lab -------------- */
/* Deterministic by EncounterId so two readers see the same ward, and skipped
   entirely for any encounter that already has one outstanding. CollectedAt lands
   45 minutes to ~8 hours back, inside the default 12-hour window, so
   OldestPendingSince reads as a plausible wait rather than a round number. */

SET NOCOUNT ON;

INSERT clinical.LabResult
    (EncounterId, PatientId, OrderedById, TestName, CollectedAt, ResultedAt, ResultJson, Status)
SELECT
    e.EncounterId,
    e.PatientId,
    e.AttendingProviderId,
    CASE e.EncounterId % 4
        WHEN 0 THEN N'Troponin'
        WHEN 1 THEN N'CBC'
        WHEN 2 THEN N'BMP'
        ELSE        N'Lactate'
    END,
    DATEADD(MINUTE, -(45 + (e.EncounterId % 9) * 60), SYSUTCDATETIME()),
    NULL,
    NULL,
    CASE WHEN e.EncounterId % 3 = 0 THEN N'Ordered' ELSE N'Collected' END
FROM clinical.Encounter AS e
WHERE e.Status = N'Active'
  AND e.EncounterId % 5 IN (0, 1)
  AND NOT EXISTS (
        SELECT 1
        FROM clinical.LabResult AS l
        WHERE l.EncounterId = e.EncounterId
          AND l.Status IN (N'Ordered', N'Collected'));

PRINT CONCAT('Outstanding labs created this run: ', @@ROWCOUNT, '.');
GO

/* ---- Part 3: make the vitals in the window trend like patients, not counters -- */
/* Absolute values, not deltas, so a rerun recomputes the same line instead of
   compounding one - and because it recomputes the same line, the UPDATE filters
   to rows that would actually change. Only readings inside the roster's 12-hour
   window are touched; older history keeps whatever Getting Started wrote. */

SET NOCOUNT ON;

DECLARE @since DATETIME2(3) = DATEADD(HOUR, -12, SYSUTCDATETIME());

/* Batched by ENCOUNTER, never by row count. Progress is a window function over
   (EncounterId, ObservationType), so splitting a partition across two batches
   would compute a position against a fraction of the series and bend the trend.
   Encounter boundaries keep every partition whole.

   The first run on a fresh Getting Started seed rewrites every in-window reading -
   roughly 350,000 of them. As one statement that is a single long transaction
   with nothing to show for itself until it ends; if the connection drops there is
   no partial progress and no message. Batched, each pass commits on its own and
   reports, so a lost connection costs one batch and the terminal shows movement
   throughout. */
DECLARE @batchSize   INT = 25,
        @lastId      INT = 0,
        @encDone     INT = 0,
        @encTotal    INT = 0,
        @changed     INT = 0,
        @totalChanged INT = 0,
        @t0          DATETIME2(3) = SYSUTCDATETIME(),
        @msg         NVARCHAR(300);

DECLARE @ids TABLE (EncounterId INT PRIMARY KEY);

SELECT @encTotal = COUNT(*) FROM clinical.Encounter WHERE Status = N'Active';

SET @msg = CONCAT('Reshaping vitals in the window across ', @encTotal,
                  ' active encounters, ', @batchSize, ' at a time...');
RAISERROR (@msg, 0, 1) WITH NOWAIT;   -- NOWAIT: PRINT would buffer to the end

WHILE 1 = 1
BEGIN
    DELETE FROM @ids;

    INSERT @ids (EncounterId)
    SELECT TOP (@batchSize) EncounterId
    FROM clinical.Encounter
    WHERE Status = N'Active' AND EncounterId > @lastId
    ORDER BY EncounterId;

    IF NOT EXISTS (SELECT 1 FROM @ids) BREAK;

    SELECT @lastId = MAX(EncounterId) FROM @ids;

    ;WITH w AS (
        SELECT
            o.ObservationId,
            o.ValueNumeric,
            o.ObservationType,
            o.EncounterId,
            /* Position of this reading in its own series, 0.0 at the start of the
               window and 1.0 at the newest reading. cnt = 1 would divide by zero. */
            COALESCE(
                CAST(ROW_NUMBER() OVER (PARTITION BY o.EncounterId, o.ObservationType
                                        ORDER BY o.RecordedAt ASC) - 1 AS DECIMAL(12, 6))
                / NULLIF(CAST(COUNT(*) OVER (PARTITION BY o.EncounterId, o.ObservationType)
                              - 1 AS DECIMAL(12, 6)), 0),
                0) AS Progress
        FROM clinical.Observation AS o
        WHERE o.EncounterId IN (SELECT EncounterId FROM @ids)
          AND o.RecordedAt >= @since
    )
    UPDATE w
    SET ValueNumeric = shaped.NewValue
    FROM w
    CROSS APPLY (
        SELECT
            /* Baseline varies per encounter so the ward is not six identical charts. */
            Baseline = CASE w.ObservationType
                           WHEN N'HeartRate'   THEN  70 + (w.EncounterId % 11)
                           WHEN N'RespRate'    THEN  14 + (w.EncounterId % 4)
                           WHEN N'SpO2'        THEN  96 + (w.EncounterId % 3)
                           WHEN N'SystolicBP'  THEN 114 + (w.EncounterId % 17)
                           WHEN N'DiastolicBP' THEN  68 + (w.EncounterId % 9)
                           WHEN N'Temperature' THEN 36.4 + (w.EncounterId % 6) * 0.1
                       END,
            /* Signed so that "away from baseline" is the clinically worrying
               direction for each vital: rate and temperature up, pressure and
               saturation down. */
            Drift = CASE w.ObservationType
                        WHEN N'HeartRate'   THEN  34.0
                        WHEN N'RespRate'    THEN  11.0
                        WHEN N'SpO2'        THEN  -8.0
                        WHEN N'SystolicBP'  THEN -24.0
                        WHEN N'DiastolicBP' THEN -13.0
                        WHEN N'Temperature' THEN   1.7
                    END,
            /* Deteriorating walks from baseline out; improving walks from abnormal
               back in; stable never leaves. */
            Course = CASE (w.EncounterId / 5) % 5
                         WHEN 0 THEN w.Progress
                         WHEN 1 THEN 1.0 - w.Progress
                         ELSE 0.0
                     END,
            /* -1, 0 or +1, keyed on the row's own identity: a real chart wobbles,
               and a perfectly straight line reads as generated. */
            Jitter = CAST(w.ObservationId % 3 AS DECIMAL(3, 1)) - 1.0
    ) AS v
    CROSS APPLY (
        SELECT NewValue =
            CASE WHEN w.ObservationType = N'Temperature'
                 THEN ROUND(v.Baseline + v.Drift * v.Course + v.Jitter * 0.1, 1)
                 ELSE ROUND(v.Baseline + v.Drift * v.Course + v.Jitter, 0)
            END
    ) AS shaped
    /* Skip rows already carrying the shaped value. The formula depends only on
       EncounterId, ObservationId and position-in-window, all of which Part 1's
       rigid shift preserves - so on a rerun every row recomputes to what it
       already holds, and this filter turns the whole pass into a no-op. */
    WHERE w.ValueNumeric IS NULL
       OR w.ValueNumeric <> shaped.NewValue;

    SET @changed      = @@ROWCOUNT;
    SET @totalChanged = @totalChanged + @changed;
    SET @encDone      = @encDone + (SELECT COUNT(*) FROM @ids);

    SET @msg = CONCAT('  encounters ', @encDone, '/', @encTotal,
                      '  -  ', @totalChanged, ' readings changed  -  ',
                      DATEDIFF(SECOND, @t0, SYSUTCDATETIME()), 's');
    RAISERROR (@msg, 0, 1) WITH NOWAIT;
END

SET @msg = CONCAT('Vitals reshaped in the window: ', @totalChanged,
                  ' readings changed in ', DATEDIFF(SECOND, @t0, SYSUTCDATETIME()),
                  's (0 means the window was already shaped).');
RAISERROR (@msg, 0, 1) WITH NOWAIT;
GO

/* ---- Verification -------------------------------------------------------- */
/* What the roster will now see. Every column below is one the agent reads. */

SET NOCOUNT ON;

DECLARE @since DATETIME2(3) = DATEADD(HOUR, -12, SYSUTCDATETIME());

SELECT
    ActiveEncounters   = COUNT(*),
    WithVitalsInWindow = SUM(CASE WHEN v.n > 0 THEN 1 ELSE 0 END),
    WithMedsInWindow   = SUM(CASE WHEN m.n > 0 THEN 1 ELSE 0 END),
    WithNotesInWindow  = SUM(CASE WHEN n.n > 0 THEN 1 ELSE 0 END),
    WithPendingLabs    = SUM(CASE WHEN l.n > 0 THEN 1 ELSE 0 END)
FROM clinical.Encounter AS e
OUTER APPLY (SELECT n = COUNT(*) FROM clinical.Observation o
             WHERE o.EncounterId = e.EncounterId AND o.RecordedAt >= @since) AS v
OUTER APPLY (SELECT n = COUNT(*) FROM clinical.MedicationOrder mo
             WHERE mo.EncounterId = e.EncounterId AND mo.OrderedAt >= @since) AS m
OUTER APPLY (SELECT n = COUNT(*) FROM clinical.ClinicalNote cn
             WHERE cn.EncounterId = e.EncounterId AND cn.CreatedAt >= @since) AS n
OUTER APPLY (SELECT n = COUNT(*) FROM clinical.LabResult lr
             WHERE lr.EncounterId = e.EncounterId
               AND lr.Status IN (N'Ordered', N'Collected')) AS l
WHERE e.Status = N'Active';

/* The trend the agent will quote: latest against the first reading in the same
   window, which is the exact pair clinical.GetHandoffCandidates reports. One
   encounter per course, so a wrong sign or a flat line is visible here rather
   than in a model's answer. */
SELECT
    Course = CASE (e.EncounterId / 5) % 5
                 WHEN 0 THEN 'deteriorating'
                 WHEN 1 THEN 'improving'
                 ELSE 'stable'
             END,
    e.EncounterId,
    o.ObservationType,
    Earlier = MIN(CASE WHEN o.Oldest = 1 THEN o.ValueNumeric END),
    Latest  = MIN(CASE WHEN o.Newest = 1 THEN o.ValueNumeric END)
FROM clinical.Encounter AS e
CROSS APPLY (
    SELECT ob.ObservationType, ob.ValueNumeric,
           ROW_NUMBER() OVER (PARTITION BY ob.ObservationType ORDER BY ob.RecordedAt ASC)  AS Oldest,
           ROW_NUMBER() OVER (PARTITION BY ob.ObservationType ORDER BY ob.RecordedAt DESC) AS Newest
    FROM clinical.Observation AS ob
    WHERE ob.EncounterId = e.EncounterId
      AND ob.RecordedAt >= @since
) AS o
WHERE e.Status = N'Active'
  AND e.EncounterId IN (
        SELECT MIN(e2.EncounterId)
        FROM clinical.Encounter AS e2
        WHERE e2.Status = N'Active'
        GROUP BY (e2.EncounterId / 5) % 5)
  AND o.ObservationType IN (N'HeartRate', N'SpO2', N'Temperature')
GROUP BY e.EncounterId, o.ObservationType
ORDER BY Course, e.EncounterId, o.ObservationType;

/* Getting Started's future-date assertion, repeated here so a bad shift is caught at
   the moment it happens rather than three areas later. */
SELECT FutureDatedRows =
    (SELECT COUNT(*) FROM clinical.MedicationOrder WHERE OrderedAt  > SYSUTCDATETIME())
  + (SELECT COUNT(*) FROM clinical.LabResult       WHERE CollectedAt > SYSUTCDATETIME()
                                                      OR ResultedAt  > SYSUTCDATETIME())
  + (SELECT COUNT(*) FROM clinical.Observation     WHERE RecordedAt  > SYSUTCDATETIME())
  + (SELECT COUNT(*) FROM clinical.ClinicalNote    WHERE CreatedAt   > SYSUTCDATETIME());
GO
