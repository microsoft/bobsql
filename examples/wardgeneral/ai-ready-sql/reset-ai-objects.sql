/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   reset-ai-objects.sql : the "clean" option — remove AI-Ready SQL's AI objects so
                          06 → 07 → 08 → 09 can be run again from scratch
   Run order            : never part of the normal flow. Run it deliberately,
                          on its own, BEFORE re-running 06-ai-embeddings.sql.

   AI-Ready SQL's scripts create if absent and leave anything that already exists
   alone, so re-running them is safe and silent. That is the right default: it
   means a second run cannot quietly throw away hours of metered model calls.
   The cost of that default is that there is no way to rebuild — which is what
   this file is for. It is the only script in the area that drops anything.

   READ THIS BEFORE RUNNING IT
     Dropping clinical.ClinicalNoteEmbeddings discards every vector. Re-running
     06 regenerates them one HTTP round-trip per note — for the full Ward
     General corpus that is 60,000 calls, multiple hours, billed per token.
     Nothing about that is recoverable from a backup you did not take. If you
     only need to rebuild the DiskANN index, do NOT run this file: drop the
     index alone (07 recreates it in about 43 seconds and costs no model calls).

   WHAT THIS DOES NOT TOUCH, on purpose
     * clinical.ClinicalNote — the notes themselves are Getting Started's seed data,
       not an AI object. This file never touches patient data.
     * The database master key — other features hold credentials under it, so
       dropping it is a database-wide decision, not a AI-Ready SQL one.
     * clinical.AIAssistanceLog — see the note at the end of this file.

   BEFORE YOU RUN
     Replace <your-foundry> and <your-apim> throughout this file with your
     Microsoft Foundry resource name and your APIM gateway name, exactly as you
     did in 06 and 08. A credential is identified BY NAME, so a placeholder left
     in place does not error — it simply matches nothing, silently leaves the
     real credential behind, and the "clean" you thought you did was partial.
     The guard below stops that from happening.
   ============================================================================ */

/* Same guard, and same two subtleties, as 06 and 08: the pattern brackets its
   own angle characters — [<]your-foundry[>] — so your find-and-replace rewrites
   the literal being tested but NOT the pattern testing it. And it sets NOEXEC
   rather than throwing, because THROW ends only its own batch, so every batch
   after the next GO would still run — drops included. */
IF 'https://<your-foundry>.openai.azure.com/' LIKE '%[<]your-foundry[>]%'
   OR 'https://<your-apim>.azure-api.net/'    LIKE '%[<]your-apim[>]%'
BEGIN
    RAISERROR('Replace <your-foundry> and <your-apim> throughout this file before running it. See BEFORE YOU RUN above. Nothing was dropped.', 16, 1);
    SET NOEXEC ON;
END
GO

PRINT '=== AI-Ready SQL reset — dropping AI objects (dependants first) ===';
GO

/* ---- 1. Procedures ------------------------------------------------------ */
/* First, because they are the callers. Nothing depends on them.              */
IF OBJECT_ID('clinical.GenerateClinicalAssistance', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE clinical.GenerateClinicalAssistance;
    PRINT '  dropped clinical.GenerateClinicalAssistance (recreated by 08).';
END
ELSE
    PRINT '  clinical.GenerateClinicalAssistance not present.';

IF OBJECT_ID('clinical.SearchSimilarNotes', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE clinical.SearchSimilarNotes;
    PRINT '  dropped clinical.SearchSimilarNotes (recreated by 09).';
END
ELSE
    PRINT '  clinical.SearchSimilarNotes not present.';
GO

/* ---- 2. Vector index, then the vectors it indexes ----------------------- */
/* The index has to go before the table it is built on. This is the step that  */
/* costs real money to undo — see READ THIS BEFORE RUNNING IT above.           */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
BEGIN
    DROP INDEX VIX_ClinicalNoteEmbeddings_Embedding ON clinical.ClinicalNoteEmbeddings;
    PRINT '  dropped VIX_ClinicalNoteEmbeddings_Embedding (recreated by 07).';
END
ELSE
    PRINT '  VIX_ClinicalNoteEmbeddings_Embedding not present.';
GO

IF OBJECT_ID('clinical.ClinicalNoteEmbeddings', 'U') IS NOT NULL
BEGIN
    DECLARE @n INT = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings);
    DROP TABLE clinical.ClinicalNoteEmbeddings;
    PRINT '  dropped clinical.ClinicalNoteEmbeddings — DISCARDED ' + CAST(@n AS VARCHAR(20))
        + ' embeddings. 06 will regenerate them from zero, at full cost.';
END
ELSE
    PRINT '  clinical.ClinicalNoteEmbeddings not present.';
GO

/* ---- 3. External model, then its credential ----------------------------- */
/* Order matters and is the whole reason this file exists. An external model    */
/* holds a reference to its credential, so dropping the credential while the    */
/* model still exists fails with "Cannot drop the credential ... because it is  */
/* used by an external model". Dependants first, always.                        */
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'WardGeneralEmbeddingModel')
BEGIN
    DROP EXTERNAL MODEL WardGeneralEmbeddingModel;
    PRINT '  dropped WardGeneralEmbeddingModel (recreated by 06).';
END
ELSE
    PRINT '  WardGeneralEmbeddingModel not present.';
GO

IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials
           WHERE name = 'https://<your-foundry>.openai.azure.com/')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL [https://<your-foundry>.openai.azure.com/];
    PRINT '  dropped the Foundry credential (recreated by 06).';
END
ELSE
    PRINT '  Foundry credential not present.';
GO

/* The gateway credential only exists if you deployed with the APIM gateway.   */
/* Not finding it is a normal outcome, not a failure.                          */
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials
           WHERE name = 'https://<your-apim>.azure-api.net/')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL [https://<your-apim>.azure-api.net/];
    PRINT '  dropped the gateway credential (recreated by 08).';
END
ELSE
    PRINT '  Gateway credential not present (expected if you deployed -NoGateway).';
GO

/* ---- 4. Proof: what is left --------------------------------------------- */
SELECT name AS remaining_credential FROM sys.database_scoped_credentials;
SELECT name AS remaining_external_model FROM sys.external_models;
GO

PRINT 'reset-ai-objects.sql complete. Re-run 06-ai-embeddings.sql to rebuild.';
GO

SET NOEXEC OFF;
GO

/* ---- Why clinical.AIAssistanceLog is deliberately left standing ---------- */
/* It is an APPEND_ONLY_LEDGER_TABLE — a tamper-evident audit trail of every   */
/* AI assistance call. Not deleting it is the entire point of a ledger table,  */
/* so a routine "clean" has no business removing one.                          */
/*                                                                             */
/* Dropping it is also not the clean break it looks like. The engine SOFT      */
/* deletes a ledger table: it renames it to                                    */
/*   MSSQL_DroppedLedgerTable_AIAssistanceLog_<guid>                           */
/* and keeps it, with its contents, for the life of the database. There is no  */
/* documented way to remove that retention table. OBJECT_ID() then returns     */
/* NULL for the original name, so an IF-NOT-EXISTS guard happily tries to      */
/* recreate — and any constraint you NAMED explicitly is still held by the     */
/* retained copy, because constraint names are unique database-wide. The error */
/* names a constraint on a table that appears not to exist. (This is why 08    */
/* declares the CreatedAt DEFAULT without naming it.)                          */
/*                                                                             */
/* 08 recreates the table only if it is absent, so leaving it here is safe: a  */
/* rebuilt AI layer simply keeps appending to the existing audit trail. If you */
/* genuinely want a new one, accept the permanent residue and uncomment: */

-- DROP TABLE clinical.AIAssistanceLog;
