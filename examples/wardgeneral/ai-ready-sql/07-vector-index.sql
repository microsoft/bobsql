/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   07-vector-index.sql : AI layer 2 of 3 — the DiskANN vector index
   Run order           : after 06-ai-embeddings.sql, before 08-ai-assistance.sql

   One statement, its own file. The index is separable from the vectors it
   covers: 06 spends hours of metered model calls building the embeddings and
   you never want to repeat that by accident, whereas this index is quick to
   build and safe to throw away. Keeping them apart means you can rebuild the
   index — after a bulk reload, or to change METRIC — without going anywhere
   near the corpus.

   Why a DiskANN vector index here (Hyperscale close):
     The latest-version DiskANN index on Azure SQL Database is UPDATEABLE —
     INSERT/UPDATE/DELETE keep the index current in real time, so the app can
     write new notes and have them become searchable with no rebuild and no
     read-only window. Earlier index versions (and the TOP_N parameter) are
     deprecated; this example uses SELECT TOP (N) WITH APPROXIMATE only.
     ref: https://learn.microsoft.com/azure/azure-sql/database/doc-changes-updates-release-notes-whats-new  (accessed 2026-07-20)

   Because the index is updateable, re-running this script after adding notes
   is unnecessary — new rows are indexed as they land. 10-updateable-index-proof.sql
   demonstrates exactly that, if you want to watch it happen rather than take
   this comment's word for it.

   PREREQUISITES:
     * 06-ai-embeddings.sql already run, with at least 100 embedded notes.

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

/* DiskANN needs at least 100 rows to build. Below that, VECTOR_SEARCH still
   works via exact scan (instant on small tables), so both procedures are
   functional either way — the index just makes them scale. */
PRINT '=== Creating DiskANN vector index (if >= 100 notes) ===';
GO

DECLARE @rows INT = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings WHERE Embedding IS NOT NULL);

IF @rows >= 100
BEGIN
    /* Create-if-absent. An existing index is LEFT ALONE — building DiskANN over  */
    /* the full corpus is real work (43 s over 60,000 vectors on HS_Gen5_8), and   */
    /* silently rebuilding it on every re-run is exactly the kind of hidden cost   */
    /* this area's scripts avoid. To rebuild deliberately, see the teardown at  */
    /* the end of this file.                                                       */
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
    BEGIN
        CREATE VECTOR INDEX VIX_ClinicalNoteEmbeddings_Embedding
        ON clinical.ClinicalNoteEmbeddings (Embedding)
        WITH (METRIC = 'cosine', TYPE = 'diskann');

        PRINT '  DiskANN vector index created over ' + CAST(@rows AS VARCHAR(20)) + ' vectors.';
    END
    ELSE
        PRINT '  DiskANN vector index already exists — left alone.';
END
ELSE
    PRINT '  Only ' + CAST(@rows AS VARCHAR(20)) + ' embedded notes (< 100) — skipping index; exact scan will be used.';
GO

/* Proof it landed. */
SELECT i.name AS index_name, i.type_desc
FROM sys.indexes AS i
WHERE i.name = 'VIX_ClinicalNoteEmbeddings_Embedding';
GO

/* ---- Rebuilding the index — uncomment to start it over ------------------- */
/* Safe to run: this discards only the index, never the embeddings, so a re-run  */
/* of 07 rebuilds it without another model call. Do this if you need a newer     */
/* index generation — a newly created index picks up the latest version your     */
/* region supports, which an existing one does not.                             */
/*                                                                               */
/* This is the cheap reset, and usually the only one you want. To rebuild the    */
/* whole AI layer including the vectors, use reset-ai-objects.sql instead — and  */
/* read its header first, because that one is expensive to undo.                */

-- DROP INDEX VIX_ClinicalNoteEmbeddings_Embedding ON clinical.ClinicalNoteEmbeddings;

PRINT '07-vector-index.sql complete. Next: 08-ai-assistance.sql';
GO
