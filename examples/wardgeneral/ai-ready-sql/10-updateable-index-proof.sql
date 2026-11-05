/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   10-updateable-index-proof.sql : prove the DiskANN index is UPDATEABLE
   Run order                     : after 07-vector-index.sql. Nothing depends
                                   on this file — it is a demonstration, not
                                   part of the application.

   THE CLAIM (07 makes it; this file proves it):
     The latest-generation DiskANN vector index on Azure SQL Database tracks
     DML. A note written now is searchable now — no rebuild, no REORGANIZE, no
     read-only window, no "reindex after the batch load" job. Earlier index
     versions made the indexed table effectively read-only, which is exactly
     the property this script exists to disprove.

   THE EXPERIMENT:
     1. Embed a query ONCE, into @QueryVector, and never touch it again.
     2. Search. The topic is deliberately absent from the corpus, so the
        results come back weak — the nearest neighbours of something the
        hospital has never seen.
     3. INSERT one note and its embedding. Two ordinary INSERT statements.
        No DDL. Nothing named "index" appears anywhere in this step.
     4. Run the IDENTICAL search again, with the SAME @QueryVector.
        The new note is at rank 1.
     5. DELETE it and search a third time. It is gone.

   Steps 2, 4 and 5 are the same SELECT, character for character, against the
   same query vector. The only variable in the whole script is the contents of
   the table. That is the point: if the index were static, step 4 would return
   exactly what step 2 returned.

   Because the whole demonstration is ONE BATCH, @QueryVector survives across
   all three searches. Do not add a GO inside it — split the batch and you are
   re-embedding the query between searches, which quietly destroys the proof.

   SELF-REPAIRING: the demo note carries the marker DEMO-UPDATEABLE-INDEX-PROOF
   in its text, and this script deletes every note carrying that marker BEFORE
   it does anything else. Step 5 already removes the note on a clean run, so the
   entry sweep exists for the run that DIED between the insert and the delete —
   which would otherwise leave the corpus at 60,001 notes, make the BEFORE
   search below a lie, and quietly falsify the row counts Getting Started quotes.
   Re-running repairs it. So does re-running after a deliberate @CleanUp = 0.

   PREREQUISITES:
     * 06-ai-embeddings.sql has run (external model + embedded corpus).
     * 07-vector-index.sql has run and actually created the index — with fewer
       than 100 embedded notes it skips, and VECTOR_SEARCH falls back to an
       exact scan. The script would still "pass", but it would be proving
       nothing about an index.

   No placeholders to replace in this file.

   All data created by these scripts is fully synthetic. No real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* Confirm the index is really there before claiming anything about it. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
    RAISERROR('No vector index found. Run 07-vector-index.sql first — without it this proves nothing.', 16, 1);
GO

PRINT '=== Updateable DiskANN index: before / after / after-delete ===';
GO

/* ---- Entry sweep: undo any earlier run of this script ------------------- */
/* Deliberately FIRST, and marker-based rather than id-based, because the run   */
/* being cleaned up after is one that never got to tell us its NoteId.          */
/* The marker is plain text with NO LIKE metacharacters in it on purpose: a     */
/* marker written as [DEMO-...] would be read as a character class and silently  */
/* match nothing, which is a cleanup that reports success and does nothing.      */
DECLARE @Marker NVARCHAR(64) = N'%DEMO-UPDATEABLE-INDEX-PROOF%';

DELETE e
FROM clinical.ClinicalNoteEmbeddings AS e
JOIN clinical.ClinicalNote AS n ON n.NoteId = e.NoteId
WHERE n.NoteText LIKE @Marker;

DELETE FROM clinical.ClinicalNote
WHERE NoteText LIKE @Marker;

IF @@ROWCOUNT > 0
    PRINT '  Entry sweep: removed a demo note left behind by an earlier run.';
GO

/* ---- ONE BATCH. Do not insert a GO below this line. --------------------- */
SET NOCOUNT ON;

DECLARE @CleanUp BIT = 1;   /* 0 = leave the demo note in the corpus */

/* The query. Ophthalmology is not in the Ward General synthetic corpus at all,
   so before the insert the nearest neighbours are only vaguely related — which
   makes the after-shot unmistakable rather than a matter of interpretation. */
DECLARE @QueryText NVARCHAR(4000) =
    N'sudden painless loss of vision in one eye with a curtain descending across '
  + N'the visual field and a history of retinal detachment repair';

/* Embedded ONCE. Every search below uses this exact vector. */
DECLARE @QueryVector VECTOR(3072, float16) =
    AI_GENERATE_EMBEDDINGS(@QueryText USE MODEL WardGeneralEmbeddingModel);

/* Declared now, assigned later, so the marker column can be written into the
   SELECT before the row it marks exists. */
DECLARE @NewNoteId INT = NULL;

/* ---- Step 2: search BEFORE the note exists ----------------------------- */
PRINT '--- BEFORE: top 5 for the query, corpus untouched ---';

SELECT TOP (5) WITH APPROXIMATE
    n.NoteId,
    n.NoteType,
    n.CreatedAt,
    Similarity = CAST(1.0 - vs.distance AS DECIMAL(5, 4)),
    IsNewNote  = CASE WHEN n.NoteId = @NewNoteId THEN N'<== NEW' ELSE N'' END,
    Excerpt    = LEFT(n.NoteText, 120)
FROM VECTOR_SEARCH(
    TABLE      = clinical.ClinicalNoteEmbeddings AS emb,
    COLUMN     = Embedding,
    SIMILAR_TO = @QueryVector,
    METRIC     = 'cosine'
) AS vs
JOIN clinical.ClinicalNote AS n ON n.NoteId = emb.NoteId
ORDER BY vs.distance;

/* ---- Step 3: write one note, and one vector for it ---------------------- */
/* Two plain INSERTs. No index maintenance of any kind. This is what the ward
   application does every time a clinician signs a note. */
DECLARE @NoteText NVARCHAR(MAX) =
    N'Subjective: Patient reports sudden painless loss of vision in the left eye '
  + N'that began this morning, described as a grey curtain descending from above. '
  + N'Preceded by two days of floaters and photopsia. Prior retinal detachment '
  + N'repair in the right eye four years ago. No pain, no headache, no trauma.'
  + CHAR(13) + CHAR(10)
  + N'Objective: Visual acuity counting fingers in the left eye, 20/25 in the right. '
  + N'Relative afferent pupillary defect present on the left. Dilated fundoscopy '
  + N'shows a superior bullous retinal detachment involving the macula.'
  + CHAR(13) + CHAR(10)
  + N'Assessment: Acute rhegmatogenous retinal detachment, macula-off, left eye.'
  + CHAR(13) + CHAR(10)
  + N'Plan: Urgent vitreoretinal surgical referral, same-day. Strict bed rest with '
  + N'positioning as directed. Nil by mouth pending theatre. Follow up with '
  + N'ophthalmology after operative repair.'
  + CHAR(13) + CHAR(10)
  /* The marker the entry sweep looks for. Last line, so it does not disturb   */
  /* the clinical prose the embedding is generated from.                       */
  + N'DEMO-UPDATEABLE-INDEX-PROOF — synthetic demo note, safe to delete.';

DECLARE @Inserted TABLE (NoteId INT);

INSERT INTO clinical.ClinicalNote (EncounterId, AuthorProviderId, NoteType, NoteText)
OUTPUT inserted.NoteId INTO @Inserted (NoteId)
SELECT TOP (1)
    e.EncounterId,
    (SELECT TOP (1) p.ProviderId FROM ops.Provider AS p ORDER BY p.ProviderId),
    N'Consult',
    @NoteText
FROM clinical.Encounter AS e
ORDER BY e.EncounterId DESC;

SELECT @NewNoteId = NoteId FROM @Inserted;

INSERT INTO clinical.ClinicalNoteEmbeddings (NoteId, Embedding)
SELECT @NewNoteId, AI_GENERATE_EMBEDDINGS(@NoteText USE MODEL WardGeneralEmbeddingModel);

PRINT '  Inserted NoteId ' + CAST(@NewNoteId AS VARCHAR(20)) + ' and its embedding. No DDL was run.';

/* ---- Step 4: the IDENTICAL search, the SAME query vector ---------------- */
PRINT '--- AFTER: same query vector, same SELECT, one row newer ---';

SELECT TOP (5) WITH APPROXIMATE
    n.NoteId,
    n.NoteType,
    n.CreatedAt,
    Similarity = CAST(1.0 - vs.distance AS DECIMAL(5, 4)),
    IsNewNote  = CASE WHEN n.NoteId = @NewNoteId THEN N'<== NEW' ELSE N'' END,
    Excerpt    = LEFT(n.NoteText, 120)
FROM VECTOR_SEARCH(
    TABLE      = clinical.ClinicalNoteEmbeddings AS emb,
    COLUMN     = Embedding,
    SIMILAR_TO = @QueryVector,
    METRIC     = 'cosine'
) AS vs
JOIN clinical.ClinicalNote AS n ON n.NoteId = emb.NoteId
ORDER BY vs.distance;

/* ---- Step 5: DELETE tracks too, and put the corpus back ----------------- */
/* An index that only learned about inserts would be half a proof: it would
   still hand back neighbours that no longer exist. Deleting restores the
   corpus to its seeded state, so this script is safe to run repeatedly. */
IF @CleanUp = 1
BEGIN
    DELETE FROM clinical.ClinicalNoteEmbeddings WHERE NoteId = @NewNoteId;
    DELETE FROM clinical.ClinicalNote           WHERE NoteId = @NewNoteId;

    PRINT '--- AFTER DELETE: same query vector again, the new note is gone ---';

    SELECT TOP (5) WITH APPROXIMATE
        n.NoteId,
        n.NoteType,
        n.CreatedAt,
        Similarity = CAST(1.0 - vs.distance AS DECIMAL(5, 4)),
        IsNewNote  = CASE WHEN n.NoteId = @NewNoteId THEN N'<== NEW' ELSE N'' END,
        Excerpt    = LEFT(n.NoteText, 120)
    FROM VECTOR_SEARCH(
        TABLE      = clinical.ClinicalNoteEmbeddings AS emb,
        COLUMN     = Embedding,
        SIMILAR_TO = @QueryVector,
        METRIC     = 'cosine'
    ) AS vs
    JOIN clinical.ClinicalNote AS n ON n.NoteId = emb.NoteId
    ORDER BY vs.distance;

    PRINT '  Demo note removed. Corpus is back to its seeded row count.';
END
ELSE
    PRINT '  @CleanUp = 0 — demo note left in place as NoteId ' + CAST(@NewNoteId AS VARCHAR(20))
        + '. Re-running this script removes it.';
GO

PRINT '10-updateable-index-proof.sql complete.';
GO
