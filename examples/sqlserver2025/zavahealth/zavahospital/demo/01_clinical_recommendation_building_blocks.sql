/* =======================================================================
   ZavaHospital Demo – Clinical Recommendation Building Blocks
   SQL Server 2025 + NVIDIA NIM on AKS

   This script shows the four key components used to build the
   clinical recommendation pipeline:

     1. CREATE EXTERNAL MODEL  – register the NIM embedding endpoint
     2. VECTOR(1024) column    – store embeddings in a typed column
     3. AI_GENERATE_EMBEDDINGS – call NIM to generate vectors from text
     4. CREATE VECTOR INDEX    – DiskANN index for fast cosine search

   ** FOR DEMONSTRATION – do not execute (already deployed) **
   ======================================================================= */
USE zavahospital;
GO

-- -----------------------------------------------------------------------
-- 1. Register NVIDIA NIM as an External Model
--    The -query suffix bakes in input_type=query server-side so
--    AI_GENERATE_EMBEDDINGS does not need to send it separately.
-- -----------------------------------------------------------------------
CREATE EXTERNAL MODEL NIMEmbeddingModel
WITH (
    LOCATION   = 'https://nim-aks.local/v1/embeddings',
    API_FORMAT = 'OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'nvidia/nv-embedqa-e5-v5-query'
);
GO

-- -----------------------------------------------------------------------
-- 2. Table with VECTOR(1024) column
--    One row per encounter; stores the composite narrative embedding.
-- -----------------------------------------------------------------------
CREATE TABLE clinical.EncounterVectors
(
    EncounterID        INT          NOT NULL PRIMARY KEY,
    PatientID          INT          NOT NULL,
    NarrativeEmbedding VECTOR(1024) NOT NULL
);
GO

-- -----------------------------------------------------------------------
-- 3. Populate embeddings using AI_GENERATE_EMBEDDINGS
--    Builds a composite narrative from encounter data and sends it
--    to NIM for embedding. Each row gets a 1024-dim vector.
-- -----------------------------------------------------------------------
;WITH LatestVitals AS (
    SELECT vs.EncounterID, vs.HeartRate, vs.SpO2, vs.TemperatureC,
           ROW_NUMBER() OVER (PARTITION BY vs.EncounterID
                              ORDER BY vs.RecordedAt DESC) AS rn
    FROM clinical.VitalsSnapshots AS vs
),
Sym AS (
    SELECT s.EncounterID,
           STRING_AGG(s.Description, N'; ')
               WITHIN GROUP (ORDER BY s.Code) AS SymList
    FROM clinical.Symptoms AS s
    GROUP BY s.EncounterID
),
Ord AS (
    SELECT o.EncounterID,
           STRING_AGG(CONCAT(o.Details, N' (', o.Status, N')'), N'; ') AS OrdList
    FROM clinical.Orders AS o
    GROUP BY o.EncounterID
),
Note AS (
    SELECT n.EncounterID,
           STRING_AGG(n.NoteText, N' ')
               WITHIN GROUP (ORDER BY n.CreatedAt DESC) AS NoteRollup
    FROM clinical.DoctorNotes AS n
    GROUP BY n.EncounterID
)
INSERT INTO clinical.EncounterVectors (EncounterID, PatientID, NarrativeEmbedding)
SELECT
    e.EncounterID,
    e.PatientID,
    AI_GENERATE_EMBEDDINGS(
        CONCAT(
            N'Encounter ', e.EncounterID,
            N' — Reason: ', ISNULL(e.Reason, N'Unknown'), N'. ',
            N'Symptoms: ',  ISNULL(s.SymList, N'none'), N'. ',
            N'Orders: ',    ISNULL(o.OrdList, N'none'), N'. ',
            N'Latest vitals: HR ',
                COALESCE(CONVERT(NVARCHAR(10), lv.HeartRate), N'NA'), N', ',
                N'SpO2 ', COALESCE(CONVERT(NVARCHAR(10), lv.SpO2), N'NA'), N'%, ',
                N'Temp ', COALESCE(CONVERT(NVARCHAR(10), lv.TemperatureC), N'NA'), N'C. ',
            N'Notes: ', LEFT(ISNULL(n.NoteRollup, N''), 800)
        ) USE MODEL NIMEmbeddingModel
    )
FROM core.Encounters AS e
LEFT JOIN (SELECT * FROM LatestVitals WHERE rn = 1) AS lv
       ON lv.EncounterID = e.EncounterID
LEFT JOIN Sym  AS s ON s.EncounterID = e.EncounterID
LEFT JOIN Ord  AS o ON o.EncounterID = e.EncounterID
LEFT JOIN Note AS n ON n.EncounterID = e.EncounterID;
GO

-- -----------------------------------------------------------------------
-- 4. Create DiskANN Vector Index with cosine metric
--    Enables fast approximate nearest-neighbor search via VECTOR_SEARCH().
--    Requires: ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON
-- -----------------------------------------------------------------------
CREATE VECTOR INDEX encounter_vector_index
ON clinical.EncounterVectors (NarrativeEmbedding)
WITH (METRIC = 'cosine', TYPE = 'diskann', MAXDOP = 8);
GO
