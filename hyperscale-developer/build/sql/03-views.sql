/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   03-views.sql    : the digital patient chart, as a computed projection.
   Run order       : 3 of 5  (after 02-tables.sql)

   The chart is the bedside view of an admitted patient. It is NOT a stored
   blob — the normalized tables stay the source of truth. Each section
   (diagnoses, allergies, medications, latest vitals, recent labs) is its
   own helper view returning a `json` column built with JSON_OBJECTAGG /
   JSON_ARRAYAGG (GA May 2025); the composite `vPatientChart` joins them
   together by encounter.

   Conventions:
     * JSON columns in the views return the native `json` type (GA on Azure
       SQL Database). They are safe to pass through APIs unchanged.
     * Each view is CREATE OR ALTER so the file is re-runnable.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Diagnoses --------------------------------------------------------- */
CREATE OR ALTER VIEW clinical.vChartDiagnoses
AS
SELECT
    d.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'code'        : d.IcdCode,
            'description' : d.Description,
            'byProviderId': d.DiagnosedById
        )
    ) AS Diagnoses
FROM clinical.Diagnosis AS d
GROUP BY d.EncounterId;
GO

/* ---- Allergies (per patient — survives discharge) ---------------------- */
CREATE OR ALTER VIEW clinical.vChartAllergies
AS
SELECT
    a.PatientId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'substance' : a.Substance,
            'reaction'  : a.Reaction,
            'severity'  : a.Severity,
            'recordedAt': a.RecordedAt
        )
    ) AS Allergies
FROM clinical.Allergy AS a
GROUP BY a.PatientId;
GO

/* ---- Medication orders (the MAR section) ------------------------------- */
CREATE OR ALTER VIEW clinical.vChartMedications
AS
SELECT
    m.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'medication'   : m.MedicationName,
            'dose'         : m.Dose,
            'route'        : m.Route,
            'orderedById'  : m.OrderedById,
            'orderedAt'    : m.OrderedAt
        )
    ) AS Medications
FROM clinical.MedicationOrder AS m
GROUP BY m.EncounterId;
GO

/* ---- Latest vitals (most recent of each type per encounter) ------------ */
/* Ranks all Observation rows; only efficient when the caller filters by      */
/* encounter (the 04-procedures always do). Do not SELECT * FROM              */
/* vPatientChart unfiltered at scale — it would rank the whole table.         */
CREATE OR ALTER VIEW clinical.vChartLatestVitals
AS
WITH ranked AS
(
    SELECT
        o.EncounterId,
        o.ObservationType,
        o.ValueNumeric,
        o.Unit,
        o.RecordedAt,
        ROW_NUMBER() OVER (
            PARTITION BY o.EncounterId, o.ObservationType
            ORDER BY o.RecordedAt DESC
        ) AS rn
    FROM clinical.Observation AS o
)
SELECT
    r.EncounterId,
    JSON_OBJECTAGG(
        r.ObservationType :
            JSON_OBJECT(
                'value' : r.ValueNumeric,
                'unit'  : r.Unit,
                'at'    : r.RecordedAt
            )
    ) AS LatestVitals
FROM ranked AS r
WHERE r.rn = 1
GROUP BY r.EncounterId;
GO

/* ---- Recent resulted labs (last 5 per encounter) ----------------------- */
/* Ranks all resulted LabResult rows; filter by encounter (the procedures do). */
CREATE OR ALTER VIEW clinical.vChartRecentLabs
AS
WITH ranked AS
(
    SELECT
        l.EncounterId,
        l.TestName,
        l.CollectedAt,
        l.ResultedAt,
        l.ResultJson,
        ROW_NUMBER() OVER (
            PARTITION BY l.EncounterId
            ORDER BY COALESCE(l.ResultedAt, l.CollectedAt) DESC
        ) AS rn
    FROM clinical.LabResult AS l
    WHERE l.Status = N'Resulted'
)
SELECT
    r.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'test'        : r.TestName,
            'collectedAt' : r.CollectedAt,
            'resultedAt'  : r.ResultedAt,
            'result'      : r.ResultJson
        )
    ) AS RecentLabs
FROM ranked AS r
WHERE r.rn <= 5
GROUP BY r.EncounterId;
GO

/* ---- Symptoms (presenting complaints per encounter) -------------------- */
CREATE OR ALTER VIEW clinical.vChartSymptoms
AS
SELECT
    s.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'description' : s.Description,
            'severity'    : s.Severity,
            'notedAt'     : s.NotedAt
        )
    ) AS Symptoms
FROM clinical.Symptom AS s
GROUP BY s.EncounterId;
GO

/* ---- Care team (providers per encounter) ------------------------------- */
CREATE OR ALTER VIEW clinical.vChartCareTeam
AS
SELECT
    ct.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'providerId' : ct.ProviderId,
            'name'       : pr.FullName,
            'role'       : ct.TeamRole,
            'isPrimary'  : ct.IsPrimary
        )
    ) AS CareTeam
FROM clinical.CareTeamMember AS ct
JOIN ops.Provider            AS pr ON pr.ProviderId = ct.ProviderId
GROUP BY ct.EncounterId;
GO

/* ---- Imaging (last 5 studies per encounter) ---------------------------- */
CREATE OR ALTER VIEW clinical.vChartImaging
AS
WITH ranked AS
(
    SELECT
        i.EncounterId, i.Modality, i.BodySite, i.Status,
        i.OrderedAt, i.ResultedAt, i.FindingsJson,
        ROW_NUMBER() OVER (PARTITION BY i.EncounterId ORDER BY i.OrderedAt DESC) AS rn
    FROM clinical.ImagingOrder AS i
)
SELECT
    r.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'modality'   : r.Modality,
            'bodySite'   : r.BodySite,
            'status'     : r.Status,
            'orderedAt'  : r.OrderedAt,
            'resultedAt' : r.ResultedAt,
            'findings'   : r.FindingsJson
        )
    ) AS Imaging
FROM ranked AS r
WHERE r.rn <= 5
GROUP BY r.EncounterId;
GO

/* ---- Recent clinical notes (last 5 per encounter) ---------------------- */
CREATE OR ALTER VIEW clinical.vChartNotes
AS
WITH ranked AS
(
    SELECT
        n.EncounterId, n.NoteType, n.NoteText, n.AuthorProviderId, n.CreatedAt,
        ROW_NUMBER() OVER (PARTITION BY n.EncounterId ORDER BY n.CreatedAt DESC) AS rn
    FROM clinical.ClinicalNote AS n
)
SELECT
    r.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'type'         : r.NoteType,
            'text'         : r.NoteText,
            'byProviderId' : r.AuthorProviderId,
            'at'           : r.CreatedAt
        )
    ) AS RecentNotes
FROM ranked AS r
WHERE r.rn <= 5
GROUP BY r.EncounterId;
GO

/* ---- Note signals (regex-extracted structured facts from the latest note) - */
/* MODERNIZE — SQL Server 2025 REGEXP_* (RE2 engine). The clinician's free-text  */
/* note is the SAME NoteText column the AI layer embeds; here we mine it          */
/* DETERMINISTICALLY with REGEXP_SUBSTR — pulling the vitals the clinician charted */
/* in prose, the pain score, and the follow-up instruction out of the narrative   */
/* into structured fields. The pain score and follow-up exist ONLY in free text —  */
/* there is no structured column for them — so regex is the only way to query them.*/
/* Story: regex = exact extraction you can trust; the vector index over the same   */
/* column = fuzzy semantic recall. One column, two techniques.                     */
/*                                                                                 */
/* REGEXP_SUBSTR(string, pattern, start, occurrence, flags, group) — 'group' picks */
/* a capture group; backslashes are literal in T-SQL string literals, so \d / \s   */
/* pass straight to RE2. No match returns NULL, and JSON_OBJECT omits NULL keys    */
/* (ABSENT ON NULL is the default).                                                */
CREATE OR ALTER VIEW clinical.vChartNoteSignals
AS
WITH latest AS
(
    SELECT
        n.EncounterId,
        n.NoteText,
        n.CreatedAt,
        ROW_NUMBER() OVER (PARTITION BY n.EncounterId ORDER BY n.CreatedAt DESC) AS rn
    FROM clinical.ClinicalNote AS n
)
SELECT
    l.EncounterId,
    JSON_OBJECT(
        'source'        : N'latest note · regex-extracted',
        'noteAt'        : l.CreatedAt,
        'bloodPressure' : REGEXP_SUBSTR(l.NoteText, 'BP\s+(\d{2,3}/\d{2,3})',            1, 1, 'i', 1),
        'heartRate'     : REGEXP_SUBSTR(l.NoteText, 'HR\s+(\d{2,3})',                     1, 1, 'i', 1),
        'temperature'   : REGEXP_SUBSTR(l.NoteText, 'T\s+(\d{2}\.\d)C',                   1, 1, 'i', 1),
        'respRate'      : REGEXP_SUBSTR(l.NoteText, 'RR\s+(\d{1,2})',                     1, 1, 'i', 1),
        'spo2'          : REGEXP_SUBSTR(l.NoteText, 'SpO2\s+(\d{2,3})',                   1, 1, 'i', 1),
        'painScore'     : REGEXP_SUBSTR(l.NoteText, 'Pain scored\s+(\d{1,2})\s+out of 10', 1, 1, 'i', 1),
        'followUp'      : REGEXP_SUBSTR(l.NoteText, 'Follow up[^.]*\.',                    1, 1, 'i')
    ) AS NoteSignals
FROM latest AS l
WHERE l.rn = 1;
GO

/* ---- The patient chart ------------------------------------------------- */
/* Row per encounter. Joins the normalized facts to the per-section JSON   */
/* projections. Use procedures in 04-procedures.sql to fetch by encounter  */
/* or by bed; this view is the building block.                             */
CREATE OR ALTER VIEW clinical.vPatientChart
AS
SELECT
    /* Encounter spine */
    e.EncounterId,
    e.Status                                   AS EncounterStatus,
    e.EncounterType,
    e.AdmitTime,
    e.DischargeTime,
    e.IntakeJson,

    /* Patient */
    p.PatientId,
    p.MRN,
    p.FullName                                 AS PatientName,
    p.DateOfBirth,
    p.Sex,
    DATEDIFF(YEAR, p.DateOfBirth, SYSUTCDATETIME())
        - IIF((MONTH(p.DateOfBirth) > MONTH(SYSUTCDATETIME()))
           OR (MONTH(p.DateOfBirth) = MONTH(SYSUTCDATETIME())
               AND DAY(p.DateOfBirth) > DAY(SYSUTCDATETIME())), 1, 0) AS AgeYears,

    /* Location */
    d.DepartmentId,
    d.Name                                     AS DepartmentName,
    u.UnitId,
    u.Name                                     AS UnitName,
    b.BedId,
    b.BedNumber,

    /* Attending */
    pr.ProviderId                              AS AttendingProviderId,
    pr.FullName                                AS AttendingProviderName,
    pr.Role                                    AS AttendingProviderRole,

    /* Composite sections (json) */
    diag.Diagnoses,
    meds.Medications,
    allergy.Allergies,
    vit.LatestVitals,
    lab.RecentLabs,
    sym.Symptoms,
    team.CareTeam,
    img.Imaging,
    note.RecentNotes,
    sig.NoteSignals
FROM clinical.Encounter             AS e
JOIN clinical.Patient               AS p   ON p.PatientId    = e.PatientId
JOIN ops.Department                 AS d   ON d.DepartmentId = e.DepartmentId
JOIN ops.Provider                   AS pr  ON pr.ProviderId  = e.AttendingProviderId
LEFT JOIN ops.Bed                   AS b   ON b.BedId        = e.BedId
LEFT JOIN ops.Unit                  AS u   ON u.UnitId       = b.UnitId
LEFT JOIN clinical.vChartDiagnoses    AS diag    ON diag.EncounterId    = e.EncounterId
LEFT JOIN clinical.vChartMedications  AS meds    ON meds.EncounterId    = e.EncounterId
LEFT JOIN clinical.vChartAllergies    AS allergy ON allergy.PatientId   = p.PatientId
LEFT JOIN clinical.vChartLatestVitals AS vit     ON vit.EncounterId     = e.EncounterId
LEFT JOIN clinical.vChartRecentLabs   AS lab     ON lab.EncounterId     = e.EncounterId
LEFT JOIN clinical.vChartSymptoms     AS sym     ON sym.EncounterId     = e.EncounterId
LEFT JOIN clinical.vChartCareTeam     AS team    ON team.EncounterId    = e.EncounterId
LEFT JOIN clinical.vChartImaging      AS img     ON img.EncounterId     = e.EncounterId
LEFT JOIN clinical.vChartNotes        AS note    ON note.EncounterId    = e.EncounterId
LEFT JOIN clinical.vChartNoteSignals  AS sig     ON sig.EncounterId     = e.EncounterId;
GO

/* ---- Convenience: who is currently in which bed ------------------------ */
CREATE OR ALTER VIEW ops.vBedCensus
AS
SELECT
    u.Name              AS UnitName,
    b.BedNumber,
    b.BedStatus,
    e.EncounterId,
    p.PatientId,
    p.MRN,
    p.FullName          AS PatientName,
    pr.FullName         AS AttendingProvider,
    e.AdmitTime
FROM ops.Bed               AS b
JOIN ops.Unit              AS u  ON u.UnitId = b.UnitId
LEFT JOIN clinical.Encounter AS e ON e.BedId = b.BedId AND e.Status = N'Active'
LEFT JOIN clinical.Patient   AS p ON p.PatientId = e.PatientId
LEFT JOIN ops.Provider       AS pr ON pr.ProviderId = e.AttendingProviderId;
GO
