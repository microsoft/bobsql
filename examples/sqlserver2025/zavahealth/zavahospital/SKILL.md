---
name: zavahospital
description: 'ZavaHospital – AI-powered inpatient clinical assistant using SQL Server 2025 vector search + NVIDIA NIM on AKS. Use when: deploying zavahospital scripts, building encounter embeddings, running vector search procs, generating clinical recommendations via NIM chat, creating doctor notes search, working in zavahealth/sqlserver2025/zavahospital/.'
---

# ZavaHospital – SQL Server 2025 + NVIDIA NIM on AKS

## Architecture
- **SQL Server 2025** on localhost, Windows auth, database `zavahospital`
- **NVIDIA NIM embeddings**: `nvidia/nv-embedqa-e5-v5-query` (1024 dims, T4 GPU on AKS)
- **NVIDIA NIM chat**: `meta/llama-3.2-3b-instruct` (T4 GPU on AKS)
- **AKS cluster**: `aks-nvidianim` in `rg-nvidianim-westus2`, 2x NC4as_T4_v3 GPU nodes
- **TLS**: Self-signed cert (CN=nim-aks.local) via AKS Web App Routing (managed NGINX ingress)
- **Hostname**: `nim-aks.local` → `<aks-ingress-ip>` via hosts file
- **Content-Type fix**: NGINX annotation `proxy_set_header Content-Type "application/json"`

## Flow
```
SQL Server 2025 → HTTPS → AKS Ingress (nim-aks.local) → NIM pods
```
- Embeddings: `AI_GENERATE_EMBEDDINGS(@prompt USE MODEL NIMEmbeddingModel)` → 1024-dim vector
- Chat: `sp_invoke_external_rest_endpoint` → `https://nim-aks.local/v1/chat/completions`
- Vector search: `VECTOR_SEARCH()` with DiskANN index (cosine metric)

## Critical Facts
- **PREVIEW_FEATURES = ON** is REQUIRED — `01_schema.sql` sets `ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;` which is mandatory for `CREATE VECTOR INDEX` and `VECTOR_SEARCH()` in SQL Server 2025
- Embedding model name MUST use `-query` suffix: `nvidia/nv-embedqa-e5-v5-query`. The `-query` suffix bakes in the `input_type=query` parameter server-side — `AI_GENERATE_EMBEDDINGS` cannot send `input_type`.
- Vector dimensions are **1024** (not 1536)
- `sp_invoke_external_rest_endpoint` max timeout is **120 seconds**
- NIM rejects `application/json;charset=utf-8` — the NGINX annotation strips the charset suffix
- Chat model (llama-3.2-3b) is small — system prompt MUST include grounding facts for quality answers
- `01_schema.sql` runs against **master** (creates the database). All other scripts run against **zavahospital**.
- Script 08 and 13 call NIM to generate embeddings — they take longer than other scripts
- Post-filter compensation: `VECTOR_SEARCH()` applies JOINs/WHERE after the ANN scan, so procs over-fetch 3x

## Database Design
- **Schemas**: `ref` (reference), `core` (patients/encounters), `clinical` (vitals/notes/orders/alerts), `sec` (RLS)
- **Ledger**: `clinical.DoctorNotes` uses `LEDGER = ON (APPEND_ONLY = ON)` for audit immutability
- **RLS**: Row-Level Security predicates scope data by building/ward via `SESSION_CONTEXT`
- **ADR**: `ACCELERATED_DATABASE_RECOVERY = ON`
- **Optimized Locking**: `OPTIMIZED_LOCKING = ON`
- **Data compression**: `clinical.VitalsSnapshots` uses `DATA_COMPRESSION = ROW`

## Stored Procedures
| Proc | Purpose |
|------|---------|
| `clinical.usp_GetCurrentPatientVitals` | Latest vitals per patient (open encounters) |
| `clinical.usp_GetPatientSymptoms` | Symptoms for patient/encounter |
| `clinical.usp_GetDoctorNotes` | Doctor notes with filtering |
| `clinical.usp_CreateOrder` | Create clinical order |
| `clinical.usp_findsimilarcases` | Vector search for similar encounters (3x over-fetch) |
| `clinical.usp_clinical_recommendation` | RAG: vector search + NIM chat → structured JSON recommendation |
| `clinical.usp_search_doctor_notes` | Vector search on individual doctor notes |

## Embedding Tables
| Table | Granularity | Source |
|-------|-------------|--------|
| `clinical.EncounterVectors` | One vector per encounter | Composite narrative (reason + symptoms + orders + vitals + notes + ward) |
| `clinical.DoctorNotesEmbeddings` | One vector per doctor note | Individual `NoteText` from `clinical.DoctorNotes` |

## Script Execution Order
```powershell
# Against master (creates database):
sqlcmd -S localhost -d master -E -i 01_schema.sql

# Against zavahospital (all remaining):
sqlcmd -S localhost -d zavahospital -E -i 02_seeding.sql
sqlcmd -S localhost -d zavahospital -E -i 03_procs.sql
sqlcmd -S localhost -d zavahospital -E -i 05_dbcreds.sql -v MasterKeyPassword="<your-strong-password>"
sqlcmd -S localhost -d zavahospital -E -i 06_ai_model.sql
sqlcmd -S localhost -d zavahospital -E -i 07_embedding_table.sql
sqlcmd -S localhost -d zavahospital -E -i 08_genembeddings.sql      # calls NIM
sqlcmd -S localhost -d zavahospital -E -i 09_create_vector_index.sql
sqlcmd -S localhost -d zavahospital -E -i 10_find_similar_cases.sql
sqlcmd -S localhost -d zavahospital -E -i 11_clinical_recommendation.sql
sqlcmd -S localhost -d zavahospital -E -i 13_embeddingtable.sql     # calls NIM
sqlcmd -S localhost -d zavahospital -E -i 14_create_notes_vector_index.sql
sqlcmd -S localhost -d zavahospital -E -i 15_search_doctor_notes.sql
```

## Demo Scripts (run after deployment)
```powershell
sqlcmd -S localhost -d zavahospital -E -i 04_call_procs.sql
sqlcmd -S localhost -d zavahospital -E -i 12_call_recommendation.sql
sqlcmd -S localhost -d zavahospital -E -i 12_vector_search_exmple.sql
sqlcmd -S localhost -d zavahospital -E -i 16_call_search_doctor_notes.sql
```

## Prerequisites (before running scripts)
1. NIM on AKS deployed and pods running (see [nvidianim/SKILL.md](nvidianim/SKILL.md))
2. Hosts file: `<aks-ingress-ip> nim-aks.local` (get the IP from `kubectl get ingress -n nim`)
3. NIM TLS cert imported into Local Machine Trusted Root CAs
4. SQL Server restarted after cert import
5. `sp_invoke_external_rest_endpoint` enabled (`sp_configure`)
6. Verify NIM endpoints respond: `.\test-embedding.ps1`, `.\test-chat.ps1` in [nvidianim/](nvidianim/)

## Troubleshooting
- `AI_GENERATE_EMBEDDINGS` TLS error → import `nvidianim\k8s\tls.cer` to Trusted Root CAs, restart SQL
- Vector search returns fewer rows than expected → increase `@SearchTopN` (procs already over-fetch 3x)
- `nim-aks.local` unreachable → check hosts file, AKS ingress IP, pods running
- EXTERNAL MODEL fails → use `API_FORMAT = 'OpenAI'`, URL must end in `/v1/embeddings`
- NIM pod OOM → use llama-3.2-3b (not 8B) for chat on T4
- Chat hallucinations → add grounding facts to system prompt (3B model needs explicit context)
- `02_seeding.sql` "already seeded" → script has guard clause; drop+recreate via `01_schema.sql` first
- Script 08/13 slow → these call NIM for each row; normal for initial population

## Demo Narrative
Edge AI pattern: hospital runs SQL Server 2025 + NIM on Azure Local in their data center. Patient data never leaves the building — zero cloud API calls. Same code, same containers, same T-SQL works in cloud AKS or on-premises Azure Local.
