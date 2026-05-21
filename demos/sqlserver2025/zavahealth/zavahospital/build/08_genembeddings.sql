;WITH LatestVitals AS (
    SELECT
        vs.PatientID,
        vs.EncounterID,
        vs.HeartRate,
        vs.SpO2,
        vs.TemperatureC,
        vs.RecordedAt,
        ROW_NUMBER() OVER (PARTITION BY vs.EncounterID ORDER BY vs.RecordedAt DESC) AS rn
    FROM clinical.VitalsSnapshots AS vs
),
Sym AS (
    SELECT
        s.EncounterID,
        STRING_AGG(s.Description, N'; ') WITHIN GROUP (ORDER BY s.Code) AS SymList
    FROM clinical.Symptoms AS s
    GROUP BY s.EncounterID
),
Ord AS (
    SELECT
        o.EncounterID,
        STRING_AGG(CONCAT(o.Details, N' (', o.Status, N')'), N'; ') AS OrdList
    FROM clinical.Orders AS o
    GROUP BY o.EncounterID
),
Note AS (
    SELECT
        n.EncounterID,
        STRING_AGG(n.NoteText, N' ') WITHIN GROUP (ORDER BY n.CreatedAt DESC) AS NoteRollup
    FROM clinical.DoctorNotes AS n
    GROUP BY n.EncounterID
),
Ward AS (
    SELECT
        e.EncounterID,
        MAX(r.Ward) AS WardName
    FROM core.BedAssignments AS ba
    JOIN ref.Beds   AS b ON b.BedID  = ba.BedID
    JOIN ref.Rooms  AS r ON r.RoomID = b.RoomID
    JOIN core.Encounters AS e ON e.EncounterID = ba.EncounterID
    WHERE ba.DischargeDate IS NULL
    GROUP BY e.EncounterID
)
INSERT INTO clinical.EncounterVectors (EncounterID, PatientID, NarrativeEmbedding)
SELECT
    e.EncounterID,
    e.PatientID,
    AI_GENERATE_EMBEDDINGS(
        CONCAT(
            N'Encounter ', e.EncounterID, N' � Reason: ', ISNULL(e.Reason, N'Unknown'), N'. ',
            N'Symptoms: ', ISNULL(s.SymList, N'none'), N'. ',
            N'Orders: ',   ISNULL(o.OrdList, N'none'), N'. ',
            N'Latest vitals: ',
               N'HR ', COALESCE(CONVERT(NVARCHAR(10), lv.HeartRate), N'NA'), N', ',
               N'SpO2 ', COALESCE(CONVERT(NVARCHAR(10), lv.SpO2), N'NA'), N'%, ',
               N'Temp ', COALESCE(CONVERT(NVARCHAR(10), lv.TemperatureC), N'NA'), N'C. ',
            N'Notes: ', LEFT(ISNULL(n.NoteRollup, N''), 800), N' ',
            N'Ward: ', ISNULL(w.WardName, N'Unknown'), N'.'
        ) USE MODEL NIMEmbeddingModel
    )
FROM core.Encounters AS e
LEFT JOIN (SELECT * FROM LatestVitals WHERE rn = 1) AS lv
       ON lv.EncounterID = e.EncounterID
LEFT JOIN Sym  AS s ON s.EncounterID  = e.EncounterID
LEFT JOIN Ord  AS o ON o.EncounterID  = e.EncounterID
LEFT JOIN Note AS n ON n.EncounterID  = e.EncounterID
LEFT JOIN Ward AS w ON w.EncounterID  = e.EncounterID
