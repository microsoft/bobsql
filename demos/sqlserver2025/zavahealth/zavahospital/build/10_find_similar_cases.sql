CREATE OR ALTER PROCEDURE clinical.usp_findsimilarcases
(
    @Prompt        NVARCHAR(4000),
    @ReturnTopN    INT   = 20,     -- final rows to return (TOP in the SELECT)
    @SearchTopN    INT   = 10,     -- TOP_N inside VECTOR_SEARCH
    @MaxDistance   FLOAT = 0.45    -- cosine distance threshold
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Generate the query embedding (1024 dims from NIM nv-embedqa-e5-v5-query)
    DECLARE @q VECTOR(1024) = AI_GENERATE_EMBEDDINGS(
        @Prompt
        USE MODEL NIMEmbeddingModel
    );

    -- Over-fetch 3x to compensate for post-filtering (JOINs + WHERE run after ANN scan)
    DECLARE @FetchN INT = @SearchTopN * 3;

    -- Vector search on PRIMARY (no replica routing)
    SELECT TOP (@ReturnTopN)
        ev.EncounterID,
        ev.PatientID,
        s.Description as Symptom,
        e.Reason as EncounterReason,
        v.HeartRate,
        v.BloodPressure,
        v.TemperatureC,
        v.RespiratoryRate,
        o.Details as OrderDetails,
        dn.NoteText,
        r.distance AS SimilarityScore
    FROM VECTOR_SEARCH(
            TABLE      = clinical.EncounterVectors AS ev,
            COLUMN     = NarrativeEmbedding,
            SIMILAR_TO = @q,
            METRIC     = N'cosine',
            TOP_N      = @FetchN
        ) AS r
    JOIN clinical.Symptoms s
    ON s.EncounterID = ev.EncounterID
    JOIN core.Encounters e
    ON e.EncounterID = ev.EncounterID
    JOIN clinical.VitalsSnapshots v
    ON v.EncounterID = ev.EncounterID
    JOIN clinical.Orders o
    ON o.EncounterID = ev.EncounterID
    JOIN clinical.DoctorNotes dn
    ON dn.EncounterID = ev.EncounterID
    WHERE r.distance <= @MaxDistance
    ORDER BY r.distance ASC;  -- lower = more similar
END;
GO