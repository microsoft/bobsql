/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   06-ai-embeddings.sql : AI layer 1 of 3 — the external model + the vectors
   Run order            : first of AI-Ready SQL, after Getting Started's 05-seed.sql
                          Followed by 07-vector-index.sql.

   Turns each clinical note's free text into meaning the engine can search.
   Pipeline (all in-engine, no app tier):
     1. CREATE EXTERNAL MODEL  — register the Microsoft Foundry
                                 (Azure OpenAI) text-embedding-3-large deployment
     2. clinical.ClinicalNoteEmbeddings — one VECTOR(3072, float16) per note,
                                 in a SEPARATE table so clinical.ClinicalNote
                                 stays a plain, fully-writable OLTP table
     3. AI_GENERATE_EMBEDDINGS — vectorize NoteText

   The DiskANN vector index over those vectors is 07-vector-index.sql, kept
   separate because it is the one step you may legitimately want to rebuild on
   its own — the vectors are hours of metered work, the index is not.

   Why float16 / VECTOR(3072, float16):
     text-embedding-3-large emits 3072 dimensions natively. float32 vectors cap
     at 1998 dims; half-precision (float16) doubles that to 3996 and stores the
     full 3072 in 2 bytes/dim. Embeddings tolerate the reduced precision well.
     On Azure SQL Database this needs no PREVIEW_FEATURES flag.
     ref: https://learn.microsoft.com/sql/t-sql/data-types/vector-data-type-half-precision-float  (accessed 2026-07-20)

   PREREQUISITES (see BEFORE YOU RUN below):
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
   BEFORE YOU RUN — replace one placeholder
   ----------------------------------------------------------------------------
   A Foundry resource name is globally unique, so this script cannot ship with
   a working value baked in. Find and replace, throughout this file:

       <your-foundry>   ->  your Microsoft Foundry (Azure OpenAI) resource name

   so every https://<your-foundry>.openai.azure.com/ becomes your endpoint. If
   you named the embedding deployment something other than
   text-embedding-3-large, replace that name too.

   Why a literal and not a @variable: the credential NAME must EXACTLY equal
   the endpoint URL — SQL matches an outbound URL against a credential whose
   name is a URL prefix of it — and a credential name is an IDENTIFIER. T-SQL
   has no variables in identifier position, so the value has to be in the text
   before the batch is compiled.
   ============================================================================ */

/* Stop before doing damage if the find-and-replace above has not been done.
   Section 2 creates an external model from this hostname, so running this file
   with the placeholder intact would register a model pointed at a hostname that
   does not resolve — and nothing would look wrong until a query tried to embed.

   Two details make this guard work, and both are easy to get wrong.

   The pattern brackets the angle characters — [<]your-foundry[>] — so that your
   find-and-replace rewrites the literal being tested but NOT the pattern testing
   it. Replace both sides and the comparison reduces to "does this URL contain
   the name in this URL", which is true for every possible name, so the guard
   fires forever.

   And it sets NOEXEC rather than throwing, because THROW ends only its own
   batch — every batch after the next GO still runs, DROP included. Under NOEXEC
   the rest of the file compiles and does nothing. The last line turns it off. */
IF 'https://<your-foundry>.openai.azure.com/' LIKE '%[<]your-foundry[>]%'
BEGIN
    RAISERROR('Replace <your-foundry> throughout this file with your Microsoft Foundry resource name before running it. See the BEFORE YOU RUN block above. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---- 1. Master key + passwordless credential --------------------------- */
/* A database master key is required to hold database-scoped credentials.       */
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Ch@ngeMe_WardGeneral_2026!';
GO

/* Nothing in this file drops anything. Every object is CREATE-if-absent and is
   LEFT ALONE if it already exists, so a re-run is safe and silent — the same
   contract section 3 keeps for the embeddings table, and for the same reason:
   this script sits in front of a long, metered, expensive model run, and a
   script that quietly rebuilds its own dependencies is a script that can throw
   that run away. To rebuild any of it deliberately, use the teardown block at
   the end of this file.

   The re-run trap this avoids: an external model holds a reference to its
   credential, so a DROP of the credential while the model still references it
   fails with "Cannot drop the credential ... because it is used by an external
   model", and the CREATE behind it then fails with "already exists". Two errors
   on every re-run. A first run is unaffected, which is exactly why an ordering
   like that can survive a long time unnoticed. */
IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials
               WHERE name = 'https://<your-foundry>.openai.azure.com/')
BEGIN
    /* Passwordless: the database's managed identity authenticates to Foundry.  */
    /* (Entra-only posture — no API key on disk. Grant it "Cognitive Services   */
    /*  OpenAI User" on the Foundry resource.)                                  */
    /* The SECRET is NOT a secret — it names the token AUDIENCE. Omit it and    */
    /* every call fails in ~78 ms with "Fail to obtain or decrypt secret for    */
    /* credential", which reads like a key problem and is not.                  */
    CREATE DATABASE SCOPED CREDENTIAL [https://<your-foundry>.openai.azure.com/]
    WITH IDENTITY = 'Managed Identity',
         SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}';

    PRINT '  credential created.';
END
ELSE
    PRINT '  credential already exists — left alone.';
GO

/* ---- 2. External model: the embedding deployment ----------------------- */
/* Also create-if-absent. If yours already exists but points somewhere stale,   */
/* that is a deliberate act — see the teardown block at the end of this file.   */
IF NOT EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'WardGeneralEmbeddingModel')
BEGIN
    CREATE EXTERNAL MODEL WardGeneralEmbeddingModel
    WITH (
        LOCATION   = 'https://<your-foundry>.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings?api-version=2024-08-01-preview',
        API_FORMAT = 'Azure OpenAI',
        MODEL_TYPE = EMBEDDINGS,
        MODEL      = 'text-embedding-3-large',
        CREDENTIAL = [https://<your-foundry>.openai.azure.com/],
        /* Auto-retry transient throttling (HTTP 429) up to 10x — essential at volume  */
        /* when many AI_GENERATE_EMBEDDINGS calls hit the deployment's per-minute quota.*/
        PARAMETERS = '{"sql_rest_options":{"retry_count":10}}'
    );

    PRINT '  external model created.';
END
ELSE
    PRINT '  external model already exists — left alone.';
GO

SELECT name, model, location, api_format
FROM sys.external_models
WHERE name = 'WardGeneralEmbeddingModel';
GO

/* ---- 3. Embeddings table (separate from ClinicalNote) ------------------ */
/* Keeping the vector column out of clinical.ClinicalNote leaves the OLTP note   */
/* table lean on its INSERT path; the embedding is a 1:1 companion row keyed by  */
/* NoteId. The DiskANN index below lives only on this table.                     */
/* CREATE IF NOT EXISTS, deliberately: embedding 60k notes is a long, metered    */
/* round-trip to the model. A DROP here would silently throw that away every     */
/* time someone re-ran the script to pick up an endpoint change. Step 4 below    */
/* is already idempotent (WHERE NOT EXISTS), so re-running fills only the gaps.  */
/* To rebuild from scratch, drop the table yourself first.                       */
IF OBJECT_ID('clinical.ClinicalNoteEmbeddings', 'U') IS NULL
BEGIN
    CREATE TABLE clinical.ClinicalNoteEmbeddings
    (
        NoteId        INT                   NOT NULL,
        Embedding     VECTOR(3072, float16) NOT NULL,
        GeneratedAt   DATETIME2(3)          NOT NULL CONSTRAINT DF_NoteEmb_GeneratedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ClinicalNoteEmbeddings PRIMARY KEY CLUSTERED (NoteId),
        CONSTRAINT FK_ClinicalNoteEmbeddings_Note
            FOREIGN KEY (NoteId) REFERENCES clinical.ClinicalNote (NoteId)
    );
    PRINT '  clinical.ClinicalNoteEmbeddings created.';
END
ELSE
    PRINT '  clinical.ClinicalNoteEmbeddings already exists - keeping it (and its vectors).';
GO

/* ---- 4. Generate embeddings for every existing note -------------------- */
/* A BATCHED LOOP, and the batching is the whole point.                           */
/*                                                                                */
/* AI_GENERATE_EMBEDDINGS does not batch — it is one HTTP round-trip per row. So  */
/* a single INSERT across all ~60k notes would be ONE atomic statement running for */
/* hours, and if the connection dropped it would roll back entirely, leaving you   */
/* with nothing. Committing 1,000 rows at a time makes progress durable: whatever  */
/* finished stays finished, and a dropped connection costs you at most one batch.  */
/*                                                                                */
/* WHERE NOT EXISTS then makes every pass pick up exactly where the last one       */
/* stopped. Embedding the full corpus is a multi-hour job — longer than a          */
/* Microsoft Entra access token lives — so expect to be disconnected at least      */
/* once. That is not a failure. Reconnect and run this script again; repeat until  */
/* verify-embeddings.sql reports MISSING=0.                                        */
/*                                                                                */
/* WAITFOR paces the loop against the deployment's per-minute token limit, so the  */
/* external model's retry budget is not spent on avoidable throttling. Raise it if */
/* you see 429s; lower it if you have raised the deployment's capacity.            */
/*                                                                                */
/* To see the mechanics on a subset rather than build the whole corpus, skip the   */
/* loop and run the INSERT once on its own with TOP (n). A few hundred notes is    */
/* enough for the DiskANN index in 07 to build and for both procedures to return   */
/* real results.                                                                   */
PRINT '=== Generating embeddings for clinical.ClinicalNote ==='
GO

DECLARE @BatchSize INT      = 1000,          -- rows committed per pass
        @Pause     CHAR(8)  = '00:00:05',    -- pacing between batches
        @Rows      INT      = 1,
        @Total     INT      = 0;

WHILE @Rows > 0
BEGIN
    INSERT INTO clinical.ClinicalNoteEmbeddings (NoteId, Embedding)
    SELECT TOP (@BatchSize)
        n.NoteId,
        AI_GENERATE_EMBEDDINGS(n.NoteText USE MODEL WardGeneralEmbeddingModel)
    FROM clinical.ClinicalNote AS n
    WHERE NOT EXISTS (
            SELECT 1 FROM clinical.ClinicalNoteEmbeddings e WHERE e.NoteId = n.NoteId
          );

    SET @Rows  = @@ROWCOUNT;
    SET @Total = @Total + @Rows;

    IF @Rows > 0
    BEGIN
        /* WITH NOWAIT so progress appears live rather than buffered to the end. */
        RAISERROR('  batch committed: %d rows (session total %d)', 0, 1, @Rows, @Total) WITH NOWAIT;
        WAITFOR DELAY @Pause;
    END
END
GO

DECLARE @n INT = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings);
PRINT '  Embeddings present: ' + CAST(@n AS VARCHAR(20));
GO

PRINT '06-ai-embeddings.sql complete — external model + embeddings ready. Next: 07-vector-index.sql';
GO

/* Clear the placeholder guard, whether or not it fired, so the session is left
   executing normally. If the only output you saw was the guard's error, nothing
   above this line ran. */
SET NOEXEC OFF;
GO

/* ---- Starting over ------------------------------------------------------ */
/* Nothing in this file drops anything, so re-running it can never rebuild what
   is already there. To rebuild deliberately, run reset-ai-objects.sql first and
   then run this file again. That script is the area's only destructive one,
   which is exactly why it is separate and separately named — you cannot reach it
   by accident. Read its header before you run it: it discards every embedding,
   and regenerating them is hours of metered model calls.

   If all you want is a fresh DiskANN index, do NOT reset: drop the index alone,
   as described at the end of 07-vector-index.sql. The vectors are the expensive
   part; the index is not. */
