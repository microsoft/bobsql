# Caldova Research: Mission-Critical, at Any Scale

**Slide title:** Start small. Scale without re-architecting.

An evidence search application over a PMC corpus in Azure SQL Hyperscale. It runs the
same application contract against a 3K serverless pilot and against primary and
named-replica targets at 1M rows.

## A note on scale

This demo was built and validated against a corpus with a **one-billion-row vector
index**. What ships here targets **one million rows** instead, because that size is
repeatable: it demonstrates indexed vector search and the named-replica story while
staying practical to provision, load, and index in your own subscription. A billion-row
corpus carries storage, load, and index-build commitments that most people recreating this
demo will not want to take on.

The application contract does not change with scale. The same query shape and the same
result contract run against 10K, 100K, or 1M.

## Application dependency checks

Before publishing the app, run from this directory:

```powershell
npm ci --prefix app
npm run build --prefix app
npm run lint --prefix app
npm audit --prefix app
```

The app's Docker build uses `npm ci` to install the committed lockfile exactly.
The lockfile retains versions and integrity hashes without registry-specific
download URLs, so local feed settings are not required by container builds.
Dependency upgrades and successful local checks do not patch an existing Azure
deployment; rebuild, deploy, and verify authentication and search separately.

## How search works

The corpus was ingested with **`minishlab/potion-base-32M`** through model2vec, producing
512-dimension float32 vectors that are L2-normalized and stored in
`dbo.pmc_chunks.embedding`. Queries are embedded with the same model at request time,
which is what makes the similarity meaningful.

> Verified, not assumed: re-encoding known chunks with `potion-base-32M` reproduces the
> stored vectors exactly (cosine 1.000000). `potion-retrieval-32M` scores 0.48–0.67 against
> the same rows, so it is a different vector space and must not be used for queries.

Three retrieval modes ship for the 3K pilot:

| Mode | What it does |
|---|---|
| **Vector** | Cosine ANN over the DiskANN index. Best for natural-language questions. |
| **Keyword** | `FREETEXTTABLE` full-text ranking. Best for rare or exact domain terms. |
| **Hybrid** | Reciprocal rank fusion of both. The default. |

The larger table has the same vector shape but not the pilot's full-text index or
filtering metadata, so its compatible query profile is vector-only.

Two design decisions came out of testing and matter more than they look:

- **One result per article.** Ranking raw chunks returned five passages from the same
  paper, which looked repetitive. Results are collapsed to the best passage per document.
- **Context expansion.** Each result carries the preceding and following chunk, so a
  passage that starts mid-sentence still reads. Journal front matter and reference lists
  are excluded through a persisted `is_boilerplate` flag.

## What the timer measures

The app shows **vector search** time, not the round trip. The ANN step is materialised into
a table variable on its own and timed inside the engine with `SYSUTCDATETIME()`, so the
number excludes rank fusion, the document joins, and context expansion.

On the pilot it runs around 5 ms warm and about 25 ms on the first call after a resume.
In keyword mode there is no vector search, so the field reads `--` rather than borrowing
the round-trip number.

## Targets

| UI label | Environment key | What it is | State |
|---|---|---|---|
| `3K` | `small` | Serverless Hyperscale pilot | 2,834 passages, hybrid ready |
| `1M` | `million` | Primary demo target | Indexed 1M table |
| `Named Replica` | `replica` | Read-only compute over the demo table | Same 1M table |

A named replica shares the primary's storage, so no data is copied and the corpus stays in
one place. It is read-only and sized independently, which is exactly what a search workload
wants. The application keeps one result contract while selecting a compatible query and
table from a fixed server-side allowlist.

### Named replica notes

A named replica is read-only, so a database user for the application identity cannot be
created on the replica. Create it on the **primary**, where it then replicates:

```sql
CREATE USER [<app-identity>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<app-identity>];
```

The application also needs a network path to the server. A Container Apps environment has
many rotating outbound addresses, so per-IP firewall rules are not workable. Either enable
*Allow Azure services* on the server, or put the Container Apps environment on a VNet
behind a NAT gateway and allow that single address. The second is narrower and is the
better answer if there is time.

[deploy/create-named-replica.sh](deploy/create-named-replica.sh) records how the replica is
created. Note that `az sql db replica create` cannot make a serverless named replica: it
demands `-e` for a serverless SKU and then rejects `-e` as unrecognised, so the script uses
an ARM REST call.

## Layout

```
app/            React client + Express API (search, readiness)
embedding/      FastAPI service running the corpus embedding model
database/       Schema, corpus export and load, search SQL, retrieval evaluation
workload/       Scheduled job that exercises auto-pause and resume
staging/        Curated CC BY corpus package with its original embeddings (see ../THIRD-PARTY-NOTICES.md)
deploy/         Container Apps definition (API + embedding in one replica)
fabric-app/     Rayfin static hosting configuration
docs/           Stage script
```

## Configuration

The application takes every server and database name from the environment. Nothing is
hardcoded. See [app/.env.example](app/.env.example) for the full list.

| Variable | Purpose |
|---|---|
| `AZURE_SQL_SMALL_SERVER` / `_DATABASE` | The 3K serverless pilot |
| `AZURE_SQL_LARGE_SERVER` / `_DATABASE` | The primary holding the 1M table |
| `AZURE_SQL_REPLICA_SERVER` / `_DATABASE` | The named replica |
| `CALDOVA_DEMO_SCALE` | `10K`, `100K`, or `1M` (default) |
| `CALDOVA_ALLOWED_ORIGINS` | Comma-separated origins allowed to call the API |

### Choose a practical corpus size

`CALDOVA_DEMO_SCALE=1M` is the default and requires no extra setup when
`dbo.pmc_chunks_1M` is present.

For a lower-cost rehearsal, run
[database/create-demo-scale-table.sql](database/create-demo-scale-table.sql) against the
same database. Set its guarded `@TargetRows` value to `10000` or `100000`, approve the
script, then set `CALDOVA_DEMO_SCALE=10K` or `100K` and restart the API. Both options use
the fixed `dbo.pmc_chunks_demo` table; the readiness check reports its actual row count.

## Rebuild from scratch

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 1. Curate a corpus from a source database (read-only) and keep its embeddings
python database/export_curated_corpus.py \
  --server <source-server>.database.windows.net \
  --database <source-database> \
  --docs-per-topic 3

# 2. Check retrieval quality offline before touching a database
python database/inspect_retrieval.py

# 3. Apply schema, load, and build the indexes
python database/apply_schema.py 10-research-schema.sql.template \
  --server <pilot-server>.database.windows.net --database <pilot-database>
python database/load_curated_corpus.py --apply \
  --server <pilot-server>.database.windows.net --database <pilot-database>
python database/create_fulltext_index.py \
  --server <pilot-server>.database.windows.net --database <pilot-database>

# 4. Run it
cd embedding && uvicorn main:app --port 8081 &
cd ../app && npm install && npm run build
AZURE_SQL_SMALL_SERVER=<pilot-server>.database.windows.net \
AZURE_SQL_SMALL_DATABASE=<pilot-database> npm start
```

## Ground rules

- Timings and row counts remain live measurements from the selected table.
- The app shows `--` and an explanation when a database is not ready.
- Table identifiers are never accepted from API input; they come from a fixed server-side
  mapping.
