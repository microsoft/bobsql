/* =======================================================================
   Zava Hospital – Doctor Notes Vector Search Proc
   SQL Server 2025 + NVIDIA NIM on AKS

   Searches DoctorNotesEmbeddings for notes similar to a natural language
   prompt using cosine distance via NIM embeddings.
   ======================================================================= */
USE zavahospital;
GO

CREATE OR ALTER PROCEDURE clinical.usp_search_doctor_notes
(
    @Prompt          NVARCHAR(MAX),
    @TopN            INT            = 100,
    @MinSimilarity   DECIMAL(19,16) = 0.3   -- cosine similarity threshold (1 - distance)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @q VECTOR(1024) = AI_GENERATE_EMBEDDINGS(
        @Prompt
        USE MODEL NIMEmbeddingModel
    );

    -- Deduplicate by note template (first 80 chars), keeping the closest match
    SELECT
        NoteID,
        PatientID,
        EncounterID,
        NoteText,
        Similarity
    FROM (
        SELECT
            dn.NoteID,
            dn.PatientID,
            dn.EncounterID,
            dn.NoteText,
            (1 - s.distance) AS Similarity,
            ROW_NUMBER() OVER (
                PARTITION BY LEFT(dn.NoteText, 80)
                ORDER BY s.distance ASC
            ) AS rn
        FROM VECTOR_SEARCH(
                TABLE      = clinical.DoctorNotesEmbeddings AS e,
                COLUMN     = Embedding,
                SIMILAR_TO = @q,
                METRIC     = N'cosine',
                TOP_N      = @TopN
            ) AS s
        JOIN clinical.DoctorNotes dn
            ON dn.NoteID = e.NoteId
        WHERE (1 - s.distance) > @MinSimilarity
    ) AS ranked
    WHERE rn = 1
    ORDER BY Similarity DESC;
END;
GO
