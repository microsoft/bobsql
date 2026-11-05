# ZavaHospital – AI-Powered Hospital Demo (SQL Server 2025 + NVIDIA NIM on AKS)

Inpatient clinical assistant demo using **SQL Server 2025** vector search, DiskANN indexing, and **NVIDIA NIM on AKS** for similar-case retrieval and RAG — patient data never leaves the network. Vector search runs on the **primary** (no replica routing).

## Where to start

| You want to… | Go to |
|---|---|
| **Stand up NIM on AKS first** (required before any SQL) | [nvidianim/](nvidianim/) folder — AKS + GPU + NIM containers + ingress |
| **Deploy the demo database from scratch** | Numbered scripts `01_schema.sql` → `16_call_search_doctor_notes.sql` in the [build/](build/) folder — see [Setup Scripts](#setup-scripts-run-in-order) |
| **Present / run the demo on stage** | [demo/](demo/) folder — 5 clean walkthrough scripts (`01_…` → `05_…`) plus a slide and an SSMS Copilot prompt. These assume the DB is already deployed. |
| **Stand up the UI demos** | [DIGITAL_CHART_README.md](DIGITAL_CHART_README.md), [CLINICAL_SEARCH_APP_BUILD_SUMMARY.md](CLINICAL_SEARCH_APP_BUILD_SUMMARY.md) |

## Architecture

```
 NL prompt (e.g. "shortness of breath with fever")
      │
      ▼
 ┌──────────────────────────────────────────────────┐
 │  SQL Server 2025 (PRIMARY)                       │
 │                                                  │
 │  1. AI_GENERATE_EMBEDDINGS(@prompt               │
 │        USE MODEL NIMEmbeddingModel)              │
 │     → 1024-dim vector via NIM                    │
 │                                                  │
 │  2. VECTOR_SEARCH (DiskANN, cosine)              │
 │     → top-K encounter vectors                   │
 │     → 3x over-fetch for post-filtering          │
 │                                                  │
 │  3. JOIN encounters, vitals, symptoms, orders,   │
 │     doctor notes → return similar cases          │
 │                                                  │
 │  4. sp_invoke_external_rest_endpoint             │
 │     → NIM chat → structured care plan (JSON)     │
 └──────────────┬───────────────────────────────────┘
                │ HTTPS (TLS, self-signed)
      ┌─────────┴─────────┐
      ▼                   ▼
 AKS Ingress         AKS Ingress
 nim-aks.local       nim-aks.local
 /v1/embeddings      /v1/chat/completions
      │                   │
      ▼                   ▼
 NIM embeddings      NIM chat
 nv-embedqa-e5-v5-query   llama-3.2-3b-instruct
 (T4 GPU, 1024d)    (T4 GPU)
```

## Prerequisites

- **SQL Server 2025** with `sp_invoke_external_rest_endpoint` enabled
- **NVIDIA NIM on AKS** deployed and accessible — deployment scripts are
  bundled in [nvidianim/](nvidianim/) (see that folder's `README.md`):
  - AKS cluster with 2x NC4as_T4_v3 GPU nodes (NVIDIA T4 16GB each)
  - NIM embeddings: `nvidia/nv-embedqa-e5-v5-query` (1024 dims, `-query` suffix avoids `input_type` requirement)
  - NIM chat: `meta/llama-3.2-3b-instruct`
  - Web App Routing ingress with TLS (hostname: `nim-aks.local`)
- **NGC API key** for pulling NIM container images
- NIM self-signed TLS cert imported into SQL Server trust store + SQL restarted
- Hostname `nim-aks.local` mapped in Windows hosts file to AKS ingress IP (get it from `kubectl get ingress -n nim`)
- **Content-Type fix**: NGINX ingress annotation `proxy_set_header Content-Type "application/json"` strips charset suffix that NIM rejects
- Chat system prompt should include grounding facts — 3B model needs explicit context to avoid hallucination

## Configuration / Placeholders

The deployment scripts use `sqlcmd` `:setvar` placeholders so no secrets are
checked into the repo. Replace them before running, or pass them on the
command line with `-v`:

| Script | Variable | What it is |
|--------|----------|------------|
| `build/05_dbcreds.sql` | `MasterKeyPassword` | Database master-key password (any strong password) |
| `build/zavaces.sql` (Azure SQL only) | `MasterKeyPassword` | Database master-key password |
| `build/zavaces.sql` | `EventHubNamespace` | Event Hubs namespace, e.g. `myns` (no `.servicebus.windows.net`) |
| `build/zavaces.sql` | `EventHubName` | Event Hub name |
| `build/zavaces.sql` | `EventHubPolicy` | Shared Access Policy name with Send rights |
| `build/zavaces.sql` | `EventHubSasKey` | Primary/secondary SAS key for that policy |

Example:
```powershell
sqlcmd -S localhost -d zavahospital -E -i build\05_dbcreds.sql `
    -v MasterKeyPassword="<your-strong-password>"
```

In addition, the prerequisites refer to `<aks-ingress-ip>` — substitute the
public IP of your NIM AKS ingress (from `kubectl get ingress -n nim`).

## Key Design Decisions

- **Vector search on PRIMARY**: No replica routing — vector search uses the primary for consistency with the latest encounter data
- **Post-filter compensation**: `vector_search()` applies JOINs/WHERE *after* the ANN scan; proc over-fetches 3x (`@FetchN = @SearchTopN * 3`) and caps with `TOP (@ReturnTopN)`
- **Edge deployment**: Same containers + K8s manifests deploy on Azure Local — hospital runs SQL + NIM in their data center, zero cloud API calls
- **1024-dim embeddings**: NIM `nv-embedqa-e5-v5-query` produces 1024-dim vectors. The `-query` suffix tells NIM to treat all inputs as queries, which avoids requiring `input_type` in the request body — critical because `AI_GENERATE_EMBEDDINGS` cannot send that parameter
- **Encounter narrative embeddings**: Each encounter is embedded as a composite narrative (reason + symptoms + orders + vitals + doctor notes + ward) for holistic similarity search
- **Append-only ledger**: `clinical.DoctorNotes` uses `LEDGER = ON (APPEND_ONLY = ON)` for audit immutability
- **Row-Level Security**: RLS predicates scope data by building/ward via `SESSION_CONTEXT`

## Data Model

### Schemas
| Schema | Purpose |
|--------|---------|
| `ref` | Reference data — Buildings, Rooms, Beds, OrderTypes, AlertSeverities, ProviderRoles |
| `core` | Core entities — Patients, Encounters, BedAssignments, Providers |
| `clinical` | Clinical data — DoctorNotes (LEDGER), Symptoms, Orders, VitalsSnapshots, Alerts, EncounterVectors, DoctorNotesEmbeddings |
| `sec` | Security — RLS filter predicate `fn_PatientScopePredicate` |

### Seed Data (02_seeding.sql)
| Entity | Count |
|--------|-------|
| Buildings | 5 |
| Rooms | 800 |
| Beds | 2,400 |
| Patients | 5,000 (Seinfeld character names) |
| Encounters | 5,000 (one per patient, open) |
| Bed Assignments | 2,400 |
| Vitals Snapshots | ~15,000 |
| Doctor Notes | ~2,600 |
| Symptoms | ~6,000 |
| Orders | ~1,900 |
| Alerts | ~1,400 |

### SQL Server 2025 Features Used
| Feature | Where |
|---------|-------|
| `CREATE EXTERNAL MODEL` | `build/06_ai_model.sql` — connects embedding model to NIM on AKS |
| `AI_GENERATE_EMBEDDINGS` | `build/08_genembeddings.sql`, `build/13_embeddingtable.sql` — generate 1024-dim vectors |
| `VECTOR_SEARCH()` | `build/10_find_similar_cases.sql`, `build/15_search_doctor_notes.sql` — DiskANN ANN search |
| `CREATE VECTOR INDEX` (DiskANN) | `build/09_create_vector_index.sql` — cosine metric, MAXDOP=8 |
| `VECTOR(1024)` data type | `build/07_embedding_table.sql`, `build/13_embeddingtable.sql` |
| `sp_invoke_external_rest_endpoint` | `build/11_clinical_recommendation.sql` — call NIM chat endpoint |
| Append-only Ledger | `build/01_schema.sql` — `clinical.DoctorNotes` immutable audit trail |
| Row-Level Security | `build/01_schema.sql` — scope access by building/ward via `SESSION_CONTEXT` |
| Accelerated Database Recovery | `build/01_schema.sql` — `ACCELERATED_DATABASE_RECOVERY = ON` |
| Optimized Locking | `build/01_schema.sql` — `OPTIMIZED_LOCKING = ON` |

## Setup Scripts (run in order)

All scripts are plain T-SQL with `GO` batch separators — run them with
[`sqlcmd`](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility),
SSMS, or the VS Code MSSQL extension. The examples below use `sqlcmd` with
Windows auth against a local instance; adjust `-S` / `-U` / `-P` for your
server.

> `05_dbcreds.sql` requires `-v MasterKeyPassword="<your-strong-password>"`.
> See [Configuration / Placeholders](#configuration--placeholders).

```powershell
# Create database + schema (run against master)
sqlcmd -S localhost -d master -E -i build\01_schema.sql

# Seed data (run against zavahospital)
sqlcmd -S localhost -d zavahospital -E -i build\02_seeding.sql

# Create stored procedures
sqlcmd -S localhost -d zavahospital -E -i build\03_procs.sql

# Create master key for TLS
sqlcmd -S localhost -d zavahospital -E -i build\05_dbcreds.sql `
    -v MasterKeyPassword="<your-strong-password>"

# Create EXTERNAL MODEL pointing to NIM embeddings
sqlcmd -S localhost -d zavahospital -E -i build\06_ai_model.sql

# Create encounter embedding table + generate embeddings
sqlcmd -S localhost -d zavahospital -E -i build\07_embedding_table.sql
sqlcmd -S localhost -d zavahospital -E -i build\08_genembeddings.sql

# Create DiskANN vector index
sqlcmd -S localhost -d zavahospital -E -i build\09_create_vector_index.sql

# Create similar-cases search proc
sqlcmd -S localhost -d zavahospital -E -i build\10_find_similar_cases.sql

# Create clinical recommendation proc (vector search + NIM chat)
sqlcmd -S localhost -d zavahospital -E -i build\11_clinical_recommendation.sql

# Create doctor notes embedding table + search procs
sqlcmd -S localhost -d zavahospital -E -i build\13_embeddingtable.sql
sqlcmd -S localhost -d zavahospital -E -i build\14_create_notes_vector_index.sql
sqlcmd -S localhost -d zavahospital -E -i build\15_search_doctor_notes.sql
```

| # | Script | Purpose |
|---|--------|---------|
| 01 | `01_schema.sql` | Create `zavahospital` database, schemas, tables, RLS, ledger, ADR, optimized locking |
| 02 | `02_seeding.sql` | Seed buildings, rooms, beds, providers, patients, encounters, vitals, symptoms, orders, doctor notes, alerts |
| 03 | `03_procs.sql` | Create operational procs (`usp_GetCurrentPatientVitals`, `usp_GetPatientSymptoms`, `usp_CreateOrder`, etc.) |
| 04 | `04_call_procs.sql` | Test proc calls |
| 05 | `05_dbcreds.sql` | Create database master key (for TLS trust) |
| 06 | `06_ai_model.sql` | Create `NIMEmbeddingModel` EXTERNAL MODEL → `nim-aks.local` |
| 07 | `07_embedding_table.sql` | Create `clinical.EncounterVectors` table (VECTOR(1024)) |
| 08 | `08_genembeddings.sql` | Generate encounter narrative embeddings (composite text → NIM → vector) |
| 09 | `09_create_vector_index.sql` | Create DiskANN vector index on `EncounterVectors` (cosine) |
| 10 | `10_find_similar_cases.sql` | Create `clinical.usp_findsimilarcases` proc — vector search with 3x over-fetch |
| 11 | `11_clinical_recommendation.sql` | Create `clinical.usp_clinical_recommendation` proc — vector search + NIM chat (llama-3.2-3b) |
| 13 | `13_embeddingtable.sql` | Create `clinical.DoctorNotesEmbeddings` table + populate from NIM |
| 14 | `14_search_doctor_notes.sql` | Create `clinical.usp_search_doctor_notes` proc — vector search on doctor notes |

## Demo Scripts

For a clean stage walkthrough see [demo/](demo/). The scripts in [build/](build/)
below are the ad-hoc "call the proc" scripts used during deployment
verification:

| Script | What it shows |
|--------|---------------|
| `build/12_call_recommendation.sql` | Call `usp_clinical_recommendation` with a random patient |
| `build/16_call_search_doctor_notes.sql` | Call `usp_search_doctor_notes` ("bad migraine, blurry vision") |
| `build/04_call_procs.sql` | Call operational procs (vitals, symptoms, create order) |

## UI Demos

| File | Purpose |
|------|---------|
| `digital-chart.html` / `.js` / `.css` | Digital patient chart UI |
| `clinical-search-app.html` / `-script.js` / `-styles.css` | Clinical similarity search UI |

## Reference / Scratch Files

| File | Purpose |
|------|---------|
| `build/zavaces.sql` | Azure Event Streams credential setup (Azure SQL only, not used by the on-prem demo) |
| `ai_agent_system_prompt.md` | System prompt for radiology routing agent |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `AI_GENERATE_EMBEDDINGS` fails with TLS error | NIM cert not trusted by SQL Server | Import `k8s\tls.cer` → Local Computer Trusted Root CAs, restart SQL |
| Vector search returns fewer rows than expected | Post-filtering removes rows after ANN scan | Proc over-fetches 3x — increase `@SearchTopN` if still insufficient |
| `nim-aks.local` not reachable | Hosts file missing or AKS ingress IP changed | Run `nvidianim\switch-hostname.ps1` or update hosts file manually |
| EXTERNAL MODEL creation fails | Wrong API_FORMAT or endpoint URL | Use `API_FORMAT = 'OpenAI'`, URL must end in `/v1/embeddings` |
| NIM pod pending/OOM | T4 doesn't have enough VRAM | Use Llama 3.2 3B (not 8B) for chat; embedding model fits comfortably |

## Copilot Deployment Prompt

To have GitHub Copilot deploy and verify everything automatically, paste this prompt into a new chat:

> Deploy the zavahospital database from scratch. Run every deployment script in the README's Setup Scripts section, one at a time, using sqlcmd. After each script, check the exit code and run a verification query to confirm it worked (e.g. row counts, object existence, index status). Stop immediately if any script fails. After all deployment scripts succeed, run each demo script and show the output.

## Edge Deployment Story

This demo represents an **edge AI** pattern: a hospital runs SQL Server 2025 and NVIDIA NIM containers on **Azure Local** in their own data center. Patient data never leaves the building — zero cloud API calls. The same T-SQL code, same NIM containers, and same Kubernetes manifests deploy identically in cloud AKS or on-premises Azure Local. The clinical recommendation pipeline (vector search + LLM chat) runs entirely within the hospital's network perimeter.
