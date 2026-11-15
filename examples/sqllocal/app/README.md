# Caldova Regional Care Transfer Center

ASP.NET Core 10 application backed by the `CaldovaRegionalCare` SQL Server 2025
database. The browser uses live database records; generating a receiving briefing
executes the approved `ReceivingBriefing` skill through SQL Server and persists its
output and seven regional source groups, plus optionally retrieved historical
notes and their saved citations.

**Isolated demo only:** the app has no authentication/authorization layer.
Do not expose it publicly or use real patient data. Generated text is for
demonstration and human review, not clinical use. The default local SQL
connection trusts the server certificate; use validated TLS outside the lab.

## Source layout

- [Data](Data/README.md): parameterized SQL and stored-procedure data access.
- [Models](Models/README.md): typed request/response contracts.
- [Properties](Properties/README.md): local development launch profiles.
- [wwwroot](wwwroot/README.md): plain HTML, CSS, and JavaScript; no npm build.

## Run locally

From the public demo package root, after database setup succeeds:

```powershell
.\app\run.ps1
```

Open `http://localhost:5099` in a browser.

The default connection uses Windows integrated authentication:

```text
Server=localhost;Database=CaldovaRegionalCare;Integrated Security=true
```

Override it without editing source:

```powershell
$env:ConnectionStrings__Caldova = '<SQL Server connection string>'
.\app\run.ps1
```

## HTTP surface

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/api/health` | Verify database connectivity |
| `GET` | `/api/transfers` | Read the active transfer queue |
| `GET` | `/api/transfers/{transferNumber}` | Read transfer detail and extracted signals |
| `GET` | `/api/transfers/{transferNumber}/audit` | Read the latest 20 append-only ledger interaction records for this transfer |
| `POST` | `/api/transfers/{transferNumber}/briefings` | Build a packet, run the approved skill, and return persisted output |
| `POST` | `/api/transfers/{transferNumber}/history-search` | Search only the selected patient's dated historical notes |

## Two independent presentation segments

Generated briefings highlight **Receiving recommendations** directly below the
summary, before key context, with a tinted card, prominent border, and larger
text. These display the saved `ConfirmOnArrival` items as AI-generated
suggestions requiring clinician review.

The transfer detail screen includes **Find relevant history**, with an editable
query initially populated from the transfer concern, except that chest pressure
uses "tight squeezing feeling in the center of the chest on exertion" to
demonstrate semantic matching. The underlying transfer concern is unchanged.
The search field wraps and
grows with the query so the full text stays visible; Enter submits the search
and Shift+Enter adds a line break. Results remain inline: dates, excerpts, cosine
distance, and expandable full source records. It calls
the database-owned `ai.usp_SearchTransferHistory` procedure using Nemotron through
`CREATE EXTERNAL MODEL` / `AI_GENERATE_EMBEDDINGS`, with approximate
`VECTOR_SEARCH` over a cosine DiskANN vector index.
Install the optional vector layer and synthetic historical notes described in
the package README first. A missing/stale embedding produces a visible error.
The SQL Server preview requires the vector index to be rebuilt during explicit
embedding refresh; searches reject a missing index rather than silently falling
back to an exact scan. No application rebuild is needed for this SQL-only change.

The history endpoint accepts JSON `{"query":"aspirin reaction","topK":3}`.
Queries must contain 1 to 4000 characters; `topK` accepts 1 through 20. Each result
includes an opaque `sourceVersion` freshness token in addition to the note ID.
An unknown transfer returns 404 and missing/stale eligible embeddings return 409.

Search is a standalone preview in the transfer-detail pane. It does not select
notes, generate a briefing, or change the briefing options.

**Generate receiving briefing** is in the right-hand briefing pane, beside an
unchecked **Include relevant history (top 3)** option. SQL's
`ai.usp_GenerateTransferBriefing` owns the entire RAG workflow. With the option
enabled, it calls `ai.usp_SearchTransferHistory` using the current transfer
concern, validates and snapshots the retrieved notes, then invokes the approved
skill/model. A preview search is not required, and editing its query does not
change the RAG query. Patient/date/freshness checks still run inside SQL.

Without history, generation uses the original seven-source packet. Both paths
use the single approved `ReceivingBriefing 2.0` skill from the skill table:
current facts remain in the summary/key context, dated historical evidence
appears in a separate **Historical context** section, and each historical item
has an expandable citation to the saved packet's full note snapshot.

For `gpt-oss-20b`, SQL requests a strict JSON schema with all four output fields,
2 to 4 separate receiving recommendations, and exactly the supplied number of
historical items (zero when history is disabled). SQL still validates the
response, note IDs, and citations before saving; HTTP 200 alone is not success.
The model is explicitly instructed to return each recommendation as a separate,
unnumbered string. SQL rejects combined numbered lists and output-field names
used as recommendation text rather than displaying them as valid suggestions.

The briefing endpoint accepts an optional body:

```json
{"includeHistory": true}
```

Omitting the body or sending `{"includeHistory":false}` preserves current-facts-only
generation. Fewer than three eligible notes are allowed, including no history.
Nearest notes are not a clinical confidence judgment. The browser resets the
history option on patient changes and locks the generation controls during a call.
Missing/stale embeddings or a missing vector index return 409, not a briefing
that silently omitted requested history. Unknown transfers return 404.

For compatibility, the API still accepts the previous `historicalNotes` array
of up to three note IDs and source versions. Do not combine explicit selections
with `includeHistory:true`; that returns 400. SQL still rejects duplicate,
malformed, cross-patient, nonhistorical, or changed selections.

Fresh base setup creates tables in `01-schema.sql`, installs the ledger
table/writer with `01b-ledger.sql`, seeds the single skill and notes in
`02-seed.sql`, and deploys `03-programmability.sql` and `07-rag.sql`.
The optional vector layer (`04` through `06`) is installed separately as
described in the [database README](../database/README.md).
On an existing vector-enabled database, deploy the 2.0 skill definition/INSERT
without reseeding application data, followed by `03-programmability.sql` and
`07-rag.sql`; do not rerun the initial vector-table creation script.
Existing invocation snapshots are preserved. `Test-CaldovaHistoryRag.ps1` verifies the SQL
connection, explicit-selection compatibility, integrated top-three retrieval,
current-facts-only generation, source citations, ledger persistence, and validation
failures. It is separate from the vector-search-only test runner.

## Build

```powershell
dotnet build .\app\Caldova.TransferCenter.csproj
```

No model endpoint, prompt, skill instructions, or patient facts are embedded in
the browser. Those remain database-owned contracts.

Click **Audit** at the top of the app to open an overlay showing
completed AI interactions, status, timing, ledger transaction ID, and saved
request/response JSON. Use **Close** or Escape to return to the app.
Deploy the updated `07-rag.sql` before running
this app version. Only new completed calls are audited; earlier records are not
backfilled. This demo does not configure external database digest verification.
