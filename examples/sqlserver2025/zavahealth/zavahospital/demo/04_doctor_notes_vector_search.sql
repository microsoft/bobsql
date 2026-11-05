/* =======================================================================
   ZavaHospital Demo – Doctor Notes Vector Search Building Blocks
   SQL Server 2025 + NVIDIA NIM on AKS

   Shows how individual doctor notes are embedded and indexed for
   natural-language similarity search, plus the search procedure.

   Components:
     1. Embedding table with VECTOR(1024) column
     2. AI_GENERATE_EMBEDDINGS to vectorize each note via NIM
     3. DiskANN vector index for fast cosine search
     4. Search procedure using VECTOR_SEARCH

   ** FOR DEMONSTRATION – do not execute (already deployed) **
   ======================================================================= */
USE zavahospital;
GO

-- -----------------------------------------------------------------------
-- 1. Embedding table — one vector per doctor note
-- -----------------------------------------------------------------------
CREATE TABLE clinical.DoctorNotesEmbeddings
(
    Embedding VECTOR(1024),
    NoteId    INT NOT NULL PRIMARY KEY CLUSTERED
);
GO

-- -----------------------------------------------------------------------
-- 2. Populate embeddings from NIM (one call per note)
-- -----------------------------------------------------------------------
INSERT INTO clinical.DoctorNotesEmbeddings
SELECT AI_GENERATE_EMBEDDINGS(dn.NoteText USE MODEL NIMEmbeddingModel),
       dn.NoteID
FROM clinical.DoctorNotes dn;
GO

-- -----------------------------------------------------------------------
-- 3. DiskANN vector index for cosine similarity
-- -----------------------------------------------------------------------
CREATE VECTOR INDEX doctornotes_vector_index
ON clinical.DoctorNotesEmbeddings (Embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann', MAXDOP = 8);
GO

-- -----------------------------------------------------------------------
-- 4. Search procedure — natural language → similar doctor notes
-- -----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE clinical.usp_search_doctor_notes
(
    @Prompt          NVARCHAR(MAX),
    @TopN            INT            = 100,
    @MinSimilarity   DECIMAL(19,16) = 0.3
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @q VECTOR(1024) = AI_GENERATE_EMBEDDINGS(
        @Prompt USE MODEL NIMEmbeddingModel
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
