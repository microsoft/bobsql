/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   06-ai-embeddings.sql : AI layer 1 of 2 — vector embeddings + DiskANN index
   Run order            : 6 of 7  (after 05-seed.sql)

   Turns each clinical note's free text into meaning the engine can search.
   Pipeline (all in-engine, no app tier):
     1. CREATE EXTERNAL MODEL  — register the Collier Health Microsoft Foundry
                                 (Azure OpenAI) text-embedding-3-large deployment
     2. clinical.ClinicalNoteEmbeddings — one VECTOR(3072, float16) per note,
                                 in a SEPARATE table so clinical.ClinicalNote
                                 stays a plain, fully-writable OLTP table
     3. AI_GENERATE_EMBEDDINGS — vectorize NoteText
     4. CREATE VECTOR INDEX    — DiskANN (updateable) for fast ANN search

   Why float16 / VECTOR(3072, float16):
     text-embedding-3-large emits 3072 dimensions natively. float32 vectors cap
     at 1998 dims; half-precision (float16) doubles that to 3996 and stores the
     full 3072 in 2 bytes/dim. Embeddings tolerate the reduced precision well.
     On Azure SQL Database this needs no PREVIEW_FEATURES flag.
     ref: https://learn.microsoft.com/sql/t-sql/data-types/vector-data-type-half-precision-float  (accessed 2026-07-20)

   Why a DiskANN vector index here (Hyperscale close):
     The latest-version DiskANN index on Azure SQL Database is UPDATEABLE —
     INSERT/UPDATE/DELETE keep the index current in real time, so the app can
     write new notes and have them become searchable with no rebuild and no
     read-only window. Earlier index versions (and the TOP_N parameter) are
     deprecated; this kit uses SELECT TOP (N) WITH APPROXIMATE only.
     ref: https://learn.microsoft.com/azure/azure-sql/database/doc-changes-updates-release-notes-whats-new  (accessed 2026-07-20)

   PREREQUISITES (fill these in for your event — see PLACEHOLDERS below):
     * A Microsoft Foundry (Azure OpenAI) resource with a text-embedding-3-large
       deployment.
     * The wardgeneral database's managed identity granted the
       "Cognitive Services OpenAI User" role on that resource (passwordless).

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

/* ============================================================================
   PLACEHOLDERS — replace before running at a new event
   ----------------------------------------------------------------------------
   @@FoundryEndpoint  : https://<your-foundry-resource>.openai.azure.com/
   embeddings deploy  : text-embedding-3-large   (deployment name)
   The credential NAME must EXACTLY equal the endpoint URL (SQL matches the
   outbound URL against a credential whose name is a URL prefix of it).
   ============================================================================ */

/* ---- 1. Master key + passwordless credential --------------------------- */
/* A database master key is required to hold database-scoped credentials.       */
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Ch@ngeMe_WardGeneral_2026!';
GO

/* Passwordless: the database's managed identity authenticates to Foundry.      */
/* (Entra-only posture — no API key on disk. Grant it "Cognitive Services       */
/*  OpenAI User" on the Foundry resource.)                                       */
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials
           WHERE name = 'https://collierhealth-ai.openai.azure.com/')
    DROP DATABASE SCOPED CREDENTIAL [https://collierhealth-ai.openai.azure.com/];
GO

CREATE DATABASE SCOPED CREDENTIAL [https://collierhealth-ai.openai.azure.com/]
WITH IDENTITY = 'Managed Identity',
     SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO

/* ---- 2. External model: the embedding deployment ----------------------- */
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'WardGeneralEmbeddingModel')
    DROP EXTERNAL MODEL WardGeneralEmbeddingModel;
GO

CREATE EXTERNAL MODEL WardGeneralEmbeddingModel
WITH (
    LOCATION   = 'https://collierhealth-ai.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings?api-version=2024-08-01-preview',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'text-embedding-3-large',
    CREDENTIAL = [https://collierhealth-ai.openai.azure.com/],
    /* Auto-retry transient throttling (HTTP 429) up to 10x — essential at volume  */
    /* when many AI_GENERATE_EMBEDDINGS calls hit the deployment's per-minute quota.*/
    PARAMETERS = '{"sql_rest_options":{"retry_count":10}}'
);
GO

SELECT name, model, location, api_format
FROM sys.external_models
WHERE name = 'WardGeneralEmbeddingModel';
GO

/* ---- 3. Embeddings table (separate from ClinicalNote) ------------------ */
/* Keeping the vector column out of clinical.ClinicalNote leaves the OLTP note   */
/* table lean on its INSERT path; the embedding is a 1:1 companion row keyed by  */
/* NoteId. The DiskANN index below lives only on this table.                     */
IF OBJECT_ID('clinical.ClinicalNoteEmbeddings', 'U') IS NOT NULL
    DROP TABLE clinical.ClinicalNoteEmbeddings;
GO

CREATE TABLE clinical.ClinicalNoteEmbeddings
(
    NoteId        INT                   NOT NULL,
    Embedding     VECTOR(3072, float16) NOT NULL,
    GeneratedAt   DATETIME2(3)          NOT NULL CONSTRAINT DF_NoteEmb_GeneratedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ClinicalNoteEmbeddings PRIMARY KEY CLUSTERED (NoteId),
    CONSTRAINT FK_ClinicalNoteEmbeddings_Note
        FOREIGN KEY (NoteId) REFERENCES clinical.ClinicalNote (NoteId)
);
GO

/* ---- 4. Generate embeddings for every existing note -------------------- */
/* For a SMALL seeded note set this single set-based INSERT is fine. For the      */
/* full ~60k-note corpus, DON'T run this statement — the Entra access token       */
/* expires (~1 hr) mid-run and a 3.5 hr single connection is dropped. Instead use */
/* deploy/generate-embeddings.ps1, a token-refreshing, resumable CHUNK driver     */
/* (WHERE NOT EXISTS makes it idempotent) that also rides the deployment quota.   */
PRINT '=== Generating embeddings for clinical.ClinicalNote ==='
GO

INSERT INTO clinical.ClinicalNoteEmbeddings (NoteId, Embedding)
SELECT
    n.NoteId,
    AI_GENERATE_EMBEDDINGS(n.NoteText USE MODEL WardGeneralEmbeddingModel)
FROM clinical.ClinicalNote AS n
WHERE NOT EXISTS (
        SELECT 1 FROM clinical.ClinicalNoteEmbeddings e WHERE e.NoteId = n.NoteId
      );
GO

DECLARE @n INT = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings);
PRINT '  Embeddings present: ' + CAST(@n AS VARCHAR(20));
GO

/* ---- 5. DiskANN vector index (updateable) ------------------------------ */
/* DiskANN needs at least 100 rows to build. Below that, VECTOR_SEARCH still     */
/* works via exact scan (instant on small tables), so the assistance proc        */
/* is functional either way — the index just makes it scale.                     */
PRINT '=== Creating DiskANN vector index (if >= 100 notes) ==='
GO

DECLARE @rows INT = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings WHERE Embedding IS NOT NULL);

IF @rows >= 100
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
        DROP INDEX VIX_ClinicalNoteEmbeddings_Embedding ON clinical.ClinicalNoteEmbeddings;

    CREATE VECTOR INDEX VIX_ClinicalNoteEmbeddings_Embedding
    ON clinical.ClinicalNoteEmbeddings (Embedding)
    WITH (METRIC = 'cosine', TYPE = 'diskann');

    PRINT '  DiskANN vector index created.';
END
ELSE
    PRINT '  Only ' + CAST(@rows AS VARCHAR(20)) + ' notes (< 100) — skipping index; exact scan will be used.';
GO
