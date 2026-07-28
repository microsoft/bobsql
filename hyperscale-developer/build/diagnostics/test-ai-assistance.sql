/* ===========================================================================
   Ward General Hospital — Hyperscale developer demo
   diagnostics / test-ai-assistance.sql

   PURPOSE
     Exercise the in-engine clinical-assistance path END-TO-END without the
     Blazor app: it calls clinical.GenerateClinicalAssistance for one encounter
     (RAG over the clinical notes → gpt-5 via Microsoft Foundry) and proves the
     tamper-evident audit row landed in the append-only ledger table
     clinical.AIAssistanceLog.

     Use this to confirm the AI layer is healthy after a deploy, a model/gateway
     change, or a database refresh — the proc here is the exact code the app's
     "Get AI assistance" card runs.

   HOW TO RUN
     * SSMS or the VS Code MSSQL extension: connect to the wardgeneral database
       (Entra / passwordless) and run this whole script.
     * Or use the PowerShell driver in this folder (handles the access token):
         ./test-ai-assistance.ps1                 # auto-picks an encounter
         ./test-ai-assistance.ps1 -EncounterId 249

   WHAT YOU SHOULD SEE
     * One result row: EncounterId, PatientName, SuggestedTriageFlag
       (Low/Medium/High/Critical), Summary, GroundedOnNoteIds, ProcessingTimeMs.
     * LedgerRowsAfter increments by 1 vs. LedgerRowsBefore — the audit row was
       appended. (UPDATE/DELETE on this table are blocked by the ledger.)
     * A graceful "AI assistance unavailable …" summary instead of an error means
       the model call failed transiently (Foundry 5xx / timeout / content filter);
       just re-run.

   All data is synthetic — no real PHI.
   =========================================================================== */
SET NOCOUNT ON;

/* Pin a specific encounter here, or leave 0 to auto-pick an Active encounter
   that has at least one clinical note (so RAG has something to ground on). */
DECLARE @EncounterId INT = 0;

IF @EncounterId = 0
    SELECT TOP (1) @EncounterId = e.EncounterId
    FROM clinical.Encounter AS e
    WHERE e.Status = N'Active'
      AND EXISTS (SELECT 1 FROM clinical.ClinicalNote AS n WHERE n.EncounterId = e.EncounterId)
    ORDER BY e.EncounterId DESC;

DECLARE @Before BIGINT = (SELECT COUNT(*) FROM clinical.AIAssistanceLog);
PRINT CONCAT(N'Testing encounter ', @EncounterId, N'  (ledger rows before = ', @Before, N')');

EXEC clinical.GenerateClinicalAssistance
     @EncounterId    = @EncounterId,
     @ModelDeployment = N'gpt-5',
     @TopK           = 5;

DECLARE @After BIGINT = (SELECT COUNT(*) FROM clinical.AIAssistanceLog);
SELECT
    LedgerRowsBefore = @Before,
    LedgerRowsAfter  = @After,
    AuditRowAppended = CASE WHEN @After = @Before + 1 THEN N'yes' ELSE N'NO — check ledger' END;
