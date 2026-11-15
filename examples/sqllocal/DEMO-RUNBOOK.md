# Caldova Regional Care Demo Runbook

The database briefing model was migrated from Phi to `gpt-oss-20b`.
Its endpoint is `https://192.0.2.10/gpt-oss-20b/v1/chat/completions`.
The final Phi VS Code chat beat below remains the original presentation
reference and requires separate model-registration updates before rehearsal.

## Preflight

Complete preflight before the presentation. Do not provision or repair the
environment on stage.

- The Regional Care Transfer Center is running at `http://localhost:5099`.
- `http://localhost:5099/api/health` reports `Healthy` for
  `CaldovaRegionalCare`.
- The Azure portal is signed in and the Azure Local VM, AKS cluster, and Azure
  Virtual Desktop resources are ready to show.
- VS Code is open with the public demo workspace and MSSQL extension.
- The MSSQL extension is connected to `localhost`, database
  `CaldovaRegionalCare`.
- Phi-3.5 Mini from Foundry Local is available in VS Code for the final chat.
- All displayed patient and transfer records are synthetic.

## SSMS scripts to have open

Open these files in SSMS before the demo, connected to `localhost` /
`CaldovaRegionalCare`. These are deployment definitions to **display**, not
scripts to execute in full on stage. The app already calls the deployed
stored procedures.

Numbers identify deployment order, not presentation order. The environment is
already deployed; you do not need to load every script or rerun setup for the
demo. Open only the files below. Unnumbered `test-*.sql` files are verification
scripts, not presentation steps.

| What you are showing | File to open | Find these objects or statements |
| --- | --- | --- |
| Native JSON and RegEx | [03-programmability.sql](database/03-programmability.sql) | `ai.usp_ExtractSignals`: `REGEXP_MATCHES`; `ai.usp_CreateTransferPacket`: `FOR JSON PATH`, `JSON_QUERY`, and `CAST(@PacketJson AS json)` |
| External embedding model | [04-external-model.sql](database/04-external-model.sql) | `CREATE EXTERNAL MODEL CaldovaHistoryEmbeddingModel`: Nemotron endpoint, model, and credential reference |
| Vector table, embeddings, and index | [05-vector-embeddings.sql](database/05-vector-embeddings.sql) | Create the vector table, insert native embeddings from the seeded notes, and create the DiskANN index |
| Search procedure, after searching in the app | [06-vector-search.sql](database/06-vector-search.sql) | `ai.usp_SearchTransferHistory`: query embedding, approximate `VECTOR_SEARCH`, same-patient/date filtering, and result shape |
| RAG entry point | [07-rag.sql](database/07-rag.sql) | `ai.usp_GenerateTransferBriefing`: current facts, optional top-three vector retrieval, validated history snapshots, approved model call, saved citations, and audit |
| Prompt and model execution, after showing the generated briefing | [07-rag.sql](database/07-rag.sql) | `ai.usp_InvokeTransferSkill`: approved skill, grounded packet, `@RequestJson`, and `sys.sp_invoke_external_rest_endpoint` |
| Ledger implementation, after showing Audit in the app | [01b-ledger.sql](database/01b-ledger.sql) | Append-only `ai.ModelInvocationAudit` table and `ai.usp_WriteModelInvocationAudit`, called by both the success and failure paths |

Keep the invocation script open: use it first for the prompt/model call, then
return to it for ledger. In Object Explorer, show the live external model,
embedding table and vector index, stored procedures, and ledger table.
The deployment files show how those same objects were defined.

## Locked demo order

### 1. Application

**Say:** "This is Caldova's Regional Care Transfer Center. It coordinates
incoming emergency transfers using operational and clinical data held in SQL
Server."

**Show:**

1. Open `http://localhost:5099`.
2. Show the live incoming-transfer queue and select a transfer.
3. Point out the field narrative, extracted signals, destination, ETA, and the
   receiving briefing with its grounding sources.
4. Generate a receiving briefing only if a fresh invocation is part of this
   rehearsal; the action calls the real database workflow.

**Land:** "The application is thin. SQL Server owns the data, grounding packet,
approved skill, model invocation, and persisted result."

### 2. Azure portal: Azure Local VM, AKS, and Azure Virtual Desktop

**Say:** "The application, SQL data, and model inference run in Caldova's
organization-controlled Regional Care environment on connected Azure Local."

**Show in the Azure portal:**

1. The Azure Local VM hosting the application and SQL Server.
2. The AKS cluster hosting the Foundry Local model deployment.
3. The Azure Virtual Desktop resource used to enter the demo environment.

Do not describe this connected lab as disconnected Azure Local. Do not change,
restart, scale, or redeploy portal resources during the presentation.

**Land:** "Azure supplies connected management and Arc governance while this
workload remains inside the Regional Care environment."

### 3. VS Code: MSSQL connection and database scripts

**Say:** "Now we can inspect the same workflow as a database developer."

**Show:**

1. VS Code with the public demo workspace.
2. The MSSQL extension connected to `localhost` / `CaldovaRegionalCare`.
3. The ordered scripts in `database/`.
4. Point out `01-schema.sql`, `03-programmability.sql`, and
   `07-rag.sql` as the files that own the AI contract.
5. Use [03-programmability.sql](database/03-programmability.sql) next to show
   both native RegEx extraction and native JSON packet construction.

**Land:** "The schema, data contracts, and programmability are versioned as
repeatable SQL deployment scripts."

### 4. Native RegEx and JSON grounding packet

Open:

[03-programmability.sql](database/03-programmability.sql)

**Show RegEx in `ai.usp_ExtractSignals`:**

1. The field narrative selected for the transfer.
2. Active rules read from `ai.SignalRule`.
3. `CROSS APPLY REGEXP_MATCHES(n.NarrativeText, r.Pattern, r.Flags)`.
4. The named matches persisted in `ai.ExtractedSignal`.

**Say:** "SQL Server 2025 turns useful details in the unstructured field note
into governed, queryable signals. This is extraction, not model inference."

**Show JSON in `ai.usp_CreateTransferPacket`:**

1. Regular SQL queries retrieve the current transfer and patient facts.
2. `FOR JSON PATH` shapes the facts and extracted signals into JSON.
3. `JSON_QUERY` embeds the objects and arrays in one grounding packet without
   turning them into escaped strings.
4. `CAST(@PacketJson AS json)` saves the packet using the native `json` type in
   `ai.TransferPacket`, alongside its hash and seven regional source groups.

**Say:** "The database shapes relational facts and deterministic signals into
a native JSON grounding packet. No model has been called yet. Later, the RAG
procedure can add retrieved historical notes before generating the briefing."

**Land:** "RegEx extracts the signals; JSON packages the evidence. Both happen
inside SQL Server before model inference."

### 5. Approved ai.Skill table

Open:

`database/01-schema.sql`

In the MSSQL extension, show the approved row without exposing unrelated secret
material:

```sql
SELECT
    SkillName,
    SkillVersion,
    IsApproved,
    IsActive,
    JSON_VALUE(SkillJson, '$.purpose') AS Purpose,
    SkillJson
FROM ai.Skill;
```

**Say:** "The prompt contract is data. It is named, versioned, hashed, approved,
and activated independently of application code."

Point out `ReceivingBriefing` version `2.0`, its purpose, constraints, and output
contract.

The same skill handles packets with or without history. It preserves current
facts in summary/key context and puts dated historical evidence in a separate
section, with validated note IDs and saved source citations.

**Land:** "The application cannot invent a prompt; it requests an approved skill
by name and version."

### 6. Transfer skill procedure: JSON payload and sp_invoke

For the split presentation, first demonstrate **Find relevant history** in the
app. Expand a dated note, then show these SSMS tabs in order:

1. [04-external-model.sql](database/04-external-model.sql): the external
   embedding model.
2. [05-vector-embeddings.sql](database/05-vector-embeddings.sql): vector table,
   `INSERT ... SELECT` using native `AI_GENERATE_EMBEDDINGS` on notes already
   loaded by the seed script, then the DiskANN vector index.
3. [06-vector-search.sql](database/06-vector-search.sql):
   `ai.usp_SearchTransferHistory` with an ordinary `SELECT ... VECTOR_SEARCH` and
   same-patient/date filtering.

The transfer-detail search is a standalone preview, not a prerequisite.

When returning for the briefing segment, enable **Include relevant history
(top 3)** in the right-hand briefing pane, then click **Generate receiving
briefing** there. Show `database/07-rag.sql`, starting with
`ai.usp_GenerateTransferBriefing`: it optionally calls vector search using the
current transfer concern, validates the retrieved sources, and snapshots their
text into the packet before invoking the approved skill/model.
The current operational facts still come from regular SQL queries.
Expand the generated historical citation to show the exact saved source.
With the history option off, generation uses the original seven-source flow.

Open:

`database/07-rag.sql`

In the MSSQL extension, show the Foundry Local URL without selecting credential
material:

```sql
SELECT
   EndpointName,
   BaseUrl + N'/v1/chat/completions' AS ChatCompletionUrl,
   ModelId,
   IsActive
FROM ai.ModelEndpoint
WHERE IsActive = 1;
```

Point out the active endpoint:
`https://192.0.2.10/gpt-oss-20b/v1/chat/completions`.

Walk through the procedure in this order:

1. Read only an approved, active skill from `ai.Skill`.
2. Read the immutable `PacketJson` from `ai.TransferPacket`.
3. Build the system and user messages with `FOR JSON PATH`.
4. Embed messages with `JSON_QUERY` and build `@RequestJson`, the OpenAI-format
   payload containing `model`, `messages`, `temperature`, and `max_tokens`.
5. Persist the exact skill and request in `ai.ModelInvocation` before the call.
6. Show both `sys.sp_invoke_external_rest_endpoint` branches: credentialless for
   the legacy local runtime and `@credential = @CredentialName` for the
   authenticated Azure Local Gateway.
7. Parse the HTTP status with `JSON_VALUE`, then call `ai.usp_SaveTransferBriefing`
   to validate and save the response, citations, and successful ledger audit.
   The helper lives in `03-programmability.sql`; the presentation procedure
   keeps the model call visible without its detailed persistence plumbing.

**Say:** "The payload combines authoritative skill instructions with a grounded
transfer packet. SQL Server sends that JSON to gpt-oss-20b and validates the
JSON response before the application can use it."

Never display the API key, database scoped credential secret, kubeconfig, or
database master-key password.

**Land:** "The model summarizes; SQL Server controls what it sees, records the
invocation, validates the response, and preserves provenance."

### 7. Phi-3.5 Mini in VS Code Chat

**Say:** "The same Foundry Local model is also available directly to the
developer inside VS Code."

**Show:**

1. Open the VS Code chat experience.
2. Select Phi-3.5 Mini from Foundry Local.
3. Start a new Ask chat and confirm the selected model without submitting a
   clinical prompt.

Do not improvise a clinical diagnosis, prescription, or treatment prompt. This
beat demonstrates that the same local model is available to the developer.

**Land:** "The local model supports both the governed database workflow and the
developer experience inside the same Regional Care boundary."

## Close

"The application runs here. The patient data stays here. The model runs here.
And Azure still gives Caldova one place to govern it."
