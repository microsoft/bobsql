# Caldova database deployment and verification

SQL Server 2025 schema, synthetic seed data, native JSON/RegEx processing,
approved prompt contracts, chat invocation, optional historical vector search,
and append-only interaction audit. Read the [collection README](../README.md)
and complete [gateway setup](../setup/README.md) first.

All commands below run from the collection root. The database name is fixed:
`CaldovaRegionalCare`. Use an isolated lab and Windows integrated SQL
administrator access. `-C` trusts the lab SQL certificate; use a properly
validated server certificate outside a disposable lab.

## Base installation

```powershell
.\database\Setup-CaldovaDatabase.ps1 -InitializeDatabase `
    -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' `
    -ExternalIPAddress '<your-gateway-ip>'
```

Server-level `external rest endpoint enabled` must already be enabled.
The wrapper refuses to initialize an existing database; without
`-InitializeDatabase`, it requires one and refreshes repeat-safe objects.
`-ConfigureModelOnly` changes only the active chat endpoint/credential.
`-ServerInstance` overrides `localhost`. API keys are fetched privately from
Kubernetes, not supplied in a SQL script. Master-key passwords are generated,
not retained for recovery; arrange backups before keeping a database.

| File | Role / repeatability |
| --- | --- |
| [00-create-database.sql](00-create-database.sql) | Create database, compatibility 170, read-committed snapshot |
| [01-schema.sql](01-schema.sql) | Initial tables, historical-note and AI contracts; fresh database only |
| [01b-ledger.sql](01b-ledger.sql) | Append-only audit table and shared writer; repeat-safe |
| [02-seed.sql](02-seed.sql) | Initial synthetic operational/history data and approved `ReceivingBriefing 2.0`; not an upgrade script |
| [03-programmability.sql](03-programmability.sql) | Queries, extraction, packets, and validated persistence helpers |
| [04-external-model.sql](04-external-model.sql) | Optional native embedding model, requires configured credential |
| [05-vector-embeddings.sql](05-vector-embeddings.sql) | Initial vector table, embeddings, and DiskANN index; do not rerun |
| [06-vector-search.sql](06-vector-search.sql) | Search and repeat-safe embedding-refresh procedures |
| [07-rag.sql](07-rag.sql) | SQL-owned generation, approved skill/model call, and audit orchestration |

The base wrapper runs `00`/`01`/`02` only for initialization, then `01b`,
`03`, packet verification, chat endpoint configuration, and `07`. It does
not automatically install `04`/`05`/`06`.

## Optional historical vector layer

Replace `192.0.2.10` in `04-external-model.sql` and the initializer with your
gateway IP. The external model location and credential name must agree.
The expected embedding model is `nemotron-3-embed-1b-bf16`, with 2,048
dimensions stored as `VECTOR(2048, float16)`. This path needs the corresponding
SQL preview support and the seeded historical notes.

```powershell
.\setup\Initialize-FoundrySqlTests.ps1 -ApplicationVectorSearch `
    -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig'
sqlcmd -S localhost -E -C -b -i .\database\04-external-model.sql .\database\05-vector-embeddings.sql .\database\06-vector-search.sql .\database\07-rag.sql
```

The initializer enables `PREVIEW_FEATURES` and installs the embedding
credential in the application database, not the isolated test database.
First installation generates `passage: `-prefixed document embeddings and
the cosine index. For later note changes, execute
`ai.usp_RefreshHistoricalNoteEmbeddings` from the MSSQL extension. Refresh
skips unchanged input hashes and rebuilds the preview vector index explicitly.

Search uses `query: `-prefixed embeddings, same-patient/date filtering, and
demo-specific relevance thresholds. Missing/stale eligible embeddings or an
absent index cause errors. Changing models requires compatible vectors/indexes.
Current facts remain separate from dated history; citations retain snapshots
of exactly what the model received.

## Verification: choose intentionally

These are real integration tests with database writes, and some invoke models.
Inspect each file before running. A passing packet test is not inference
verification. Do not execute every test automatically.

| Test | What it checks / side effects |
| --- | --- |
| [test-packet.sql](test-packet.sql) | Approved skill and seven-source packet construction; persists a synthetic packet |
| [test-foundry-ai.sql](test-foundry-ai.sql) | One live generated/persisted briefing, seven sources, and provenance |
| [test-ai-ledger.sql](test-ai-ledger.sql) | Two live model calls; successful/failed audit, immutable UPDATE/DELETE behavior; temporary session-scoped failure trigger |
| [Test-CaldovaVectorHistory.ps1](Test-CaldovaVectorHistory.ps1) | Runs `test-vector-history.sql`: embedding regeneration/index rebuilding, ranking, isolation, freshness, and invalid input checks |
| [Test-CaldovaHistoryRag.ps1](Test-CaldovaHistoryRag.ps1) | Runs `test-history-rag.sql`: source validation plus three live persisted briefings (explicit history, integrated retrieval, current facts only) |
| [model-tests](model-tests/README.md) | Isolated chat/embedding calls in a separate database |

Examples, after setup:

```powershell
sqlcmd -S localhost -d CaldovaRegionalCare -E -C -b -i .\database\test-packet.sql
.\database\Test-CaldovaVectorHistory.ps1
.\database\Test-CaldovaHistoryRag.ps1
```

The PowerShell history runners have no overall SQL query timeout; monitor
errors rather than repeatedly restarting them. Successful AI calls and
deliberately failed audit tests leave persisted evidence in the lab database.

## Audit and cleanup limits

Completed model interactions include request/response JSON, skill snapshot,
endpoint/model, timings, status, and saved briefing IDs. Success records commit
with the briefing; failure records follow rollback. Earlier history is not
backfilled, and interrupted/pre-invocation calls are not guaranteed a completed
record. External digest storage/verification is not configured.

There is no automatic database teardown. Stop the app before intentionally
removing a dedicated lab database; removal destroys all saved demo state.
Do not delete shared Kubernetes resources as database cleanup.
