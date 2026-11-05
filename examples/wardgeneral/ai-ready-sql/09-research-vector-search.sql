/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   09-research-vector-search.sql : read-only vector search over historical notes
                                   for researchers / students on a NAMED REPLICA.
   Run order                     : after 07-vector-index.sql (needs the model +
                                   embeddings + DiskANN index). Run against the
                                   PRIMARY (read-write) — the proc and role are
                                   database objects in shared storage, so they are
                                   visible and callable on the read-only replica.

   THE STORY (Hyperscale read scale-out):
     Students search the 60k-note corpus semantically ("find notes like this")
     on a dedicated named replica — their own compute, the SAME page servers as
     the OLTP primary, no data copy and no separate vector store. The ward's
     writes on the primary are never slowed by research queries.

   This is the RETRIEVAL half of clinical.GenerateClinicalAssistance (08),
   with NO chat step — pure semantic search, safe for open-ended research.

   ------------------------------------------------------------------------------
   IMPORTANT — query embedding on a read-only replica (verified by probe):
     VECTOR_SEARCH needs a query VECTOR. This proc turns @QueryText into one with
     AI_GENERATE_EMBEDDINGS, which makes an OUTBOUND REST call (and acquires a
     managed-identity token). That this runs on the READ-ONLY named replica is
     confirmed by a live probe (verified on wardgeneral-research): the replica
     embeds AND searches — pure read scale-out, no work on the primary. If the
     replica is on a SEPARATE server, that server's managed identity must also
     have the Foundry "Cognitive Services OpenAI User" role.
   ------------------------------------------------------------------------------

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

/* ---- Retrieval-only semantic search over clinical notes -----------------
   FILTERED vector search. The three optional parameters are ordinary relational
   predicates evaluated alongside the ANN scan — the engine's iterative filtering
   keeps pulling candidates from the DiskANN graph until it can satisfy TOP (@TopK)
   with rows that also pass the WHERE clause. This is a filter, not a second
   scoring signal: nothing is blended into Similarity, and the ranking is still
   pure cosine distance.

   @NoteType defaults to Discharge deliberately. A discharge summary is the one
   note per encounter that states the whole episode — presentation, course and
   outcome in one document — so it is what a researcher almost always wants.
   Progress and Consult notes are mid-episode snapshots and make a corpus search
   noisier, not richer. Pass @NoteType = NULL to search every note type.
   ------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clinical.SearchSimilarNotes
    @QueryText NVARCHAR(MAX),                     -- free-text research query (embedded inline)
    @TopK      INT           = 10,
    @NoteType  NVARCHAR(30)  = N'Discharge',      -- NULL = all note types
    @SinceUtc  DATETIME2(3)  = NULL,              -- NULL = no lower bound on CreatedAt
    @Keyword   NVARCHAR(200) = NULL               -- NULL = no literal-term requirement
AS
BEGIN
    SET NOCOUNT ON;

    IF @QueryText IS NULL OR LEN(@QueryText) = 0
    BEGIN
        RAISERROR('Provide @QueryText to search for.', 16, 1);
        RETURN;
    END

    /* Embed the query text, then search. On a read-only replica this line requires */
    /* embed-on-replica (see header) — proven to work on wardgeneral-research.       */
    DECLARE @QueryVector VECTOR(3072, float16) =
        AI_GENERATE_EMBEDDINGS(@QueryText USE MODEL WardGeneralEmbeddingModel);

    /* Updateable DiskANN over the note corpus. Read-only: no write, safe on a      */
    /* secondary. TOP (N) WITH APPROXIMATE + VECTOR_SEARCH (no legacy TOP_N).        */
    SELECT TOP (@TopK) WITH APPROXIMATE
        n.NoteId,
        n.EncounterId,
        n.NoteType,
        n.CreatedAt,
        Similarity = CAST(1.0 - vs.distance AS DECIMAL(5, 4)),
        n.NoteText
    FROM VECTOR_SEARCH(
        TABLE      = clinical.ClinicalNoteEmbeddings AS emb,
        COLUMN     = Embedding,
        SIMILAR_TO = @QueryVector,
        METRIC     = 'cosine'
    ) AS vs
    JOIN clinical.ClinicalNote AS n ON n.NoteId = emb.NoteId
    WHERE (@NoteType IS NULL OR n.NoteType  = @NoteType)
      AND (@SinceUtc IS NULL OR n.CreatedAt >= @SinceUtc)
      AND (@Keyword  IS NULL OR n.NoteText LIKE N'%' + @Keyword + N'%')
    ORDER BY vs.distance;
END;
GO

/* ---- Least-privilege research role -------------------------------------- */
/* Created on the primary (shared storage) so it exists on the replica too.     */
/* Members get ONLY what note research needs: read the notes + embeddings, run   */
/* the search proc, and use the embedding model. No access to patients, orders,  */
/* meds, or any write path.                                                      */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'research_reader' AND type = 'R')
    CREATE ROLE research_reader;
GO

GRANT SELECT   ON clinical.ClinicalNote            TO research_reader;
GRANT SELECT   ON clinical.ClinicalNoteEmbeddings  TO research_reader;
GRANT EXECUTE  ON clinical.SearchSimilarNotes      TO research_reader;
/* Needed because the proc embeds @QueryText on the replica via AI_GENERATE_EMBEDDINGS. */
GRANT EXECUTE  ON EXTERNAL MODEL::WardGeneralEmbeddingModel TO research_reader;
GO

/* ---- Example: grant a student read-only research access (access isolation) ---
   Run the LOGIN step on the logical server that hosts the NAMED REPLICA (its
   master DB) — for true isolation that is a SEPARATE server from the primary, so
   the student's credential never exists on the primary's server. Then run the
   USER + role step here on the PRIMARY database (shared → visible on the replica).

   -- On the named replica's server (master):
   --   CREATE LOGIN [student1] WITH PASSWORD = '<strong-password>';
   -- (or, Entra:  CREATE LOGIN [student1@collier.edu] FROM EXTERNAL PROVIDER;)

   -- On the PRIMARY database (wardgeneral):
   --   CREATE USER [student1] FOR LOGIN [student1];
   --   ALTER ROLE research_reader ADD MEMBER [student1];

   Students then connect to the REPLICA only:
     Server=<replica-server>.database.windows.net; Database=wardgeneral-research
   and call:  EXEC clinical.SearchSimilarNotes @QueryText = N'elderly chest pain with elevated troponin';

   Narrowing the same search with filters (still one ANN scan, no score fusion):
     EXEC clinical.SearchSimilarNotes
          @QueryText = N'elderly chest pain with elevated troponin',
          @SinceUtc  = '2026-01-01',
          @Keyword   = N'troponin';

   Widening it to every note type:
     EXEC clinical.SearchSimilarNotes
          @QueryText = N'elderly chest pain with elevated troponin',
          @NoteType  = NULL;
   ------------------------------------------------------------------------------ */
PRINT '09-research-vector-search.sql complete — clinical.SearchSimilarNotes + research_reader role created.';
GO
