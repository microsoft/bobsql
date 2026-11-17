# Caldova

Caldova is the stage application for the Mission-Critical, at Any Scale demo:

> Start small. Scale without re-architecting.

It is a biomedical evidence explorer. A natural-language question is embedded at request
time and sent to the selected Azure SQL Hyperscale target. The target contract stays fixed,
while a server-side allowlist chooses the compatible table and query profile.

## How a search works

1. The question is sent to the embedding service, which returns 512 L2-normalized
   `float32` values.
2. That vector and the raw question are passed to the selected retrieval query.
3. The 3K target runs up to two retrievals and fuses them:
   - **Vector** — approximate nearest neighbour over the DiskANN cosine index.
   - **Keyword** — `FREETEXTTABLE` over the full-text index.
   - **Hybrid** — both, combined with reciprocal rank fusion (k = 60).
4. The scale targets run vector-only retrieval because their source table has no full-text
   index or hybrid-query metadata columns.
5. Results are deduplicated to the best passage per article and neighbouring passages are
   attached so each quote reads in context.

`VectorSearchMs` is measured inside the engine around the ANN retrieval only, so it
excludes the round trip and the embedding call. The UI reports it separately from total
time.

## Readiness and demo scale

Every target is checked before it is queried. If the database is unreachable or the index
required by that target is missing, the app reports why and leaves the timings as `--`. It
does not invent a timing. Unsupported modes and filters are also rejected instead of silently
changing their meaning.

The app opens on the 1M primary. This is the recommended default for trying the demo in
your own subscription: it is large enough to make indexed vector search credible while
staying practical to load and index.

- `CALDOVA_DEMO_SCALE=1M` uses the indexed `dbo.pmc_chunks_1M` table.
- `CALDOVA_DEMO_SCALE=10K` or `100K` uses `dbo.pmc_chunks_demo`. Create it with
   `database/create-demo-scale-table.sql`, setting `@TargetRows` to the matching value.

Restart the API after changing the value. The API reports the actual row count and never
substitutes a presentation count.

## Environments

| Key | UI label | Database table | Search profile | Verified state |
|---|---|---|---|---|
| `small` | `3K` | `dbo.pmc_chunks` on the pilot | Hybrid | 2,834 passages, ready |
| `million` | `1M` by default | `dbo.pmc_chunks_1M` or `dbo.pmc_chunks_demo` | Vector | Primary demo target |
| `replica` | `Named Replica` | Same demo table as `million` | Vector | Read-only compute |

The named replica shares the primary's storage and 1M vector index but has its own compute,
so reading through it does not compete with work on the primary. Table identifiers are not
accepted from API input; they come only from the fixed mapping in `server/index.ts`.

## Configuration

The API reads these at startup and does not load `.env` files automatically:

```bash
export AZURE_SQL_SMALL_SERVER='<pilot-server>.database.windows.net'
export AZURE_SQL_SMALL_DATABASE='<pilot-database>'
export AZURE_SQL_LARGE_SERVER='<scale-server>.database.windows.net'
export AZURE_SQL_LARGE_DATABASE='<scale-database>'
export AZURE_SQL_REPLICA_SERVER='<scale-server>.database.windows.net'
export AZURE_SQL_REPLICA_DATABASE='<replica-name>'
export CALDOVA_DEMO_SCALE='1M' # supported: 10K, 100K, 1M
export EMBEDDING_SERVICE_URL='http://127.0.0.1:8081'
```

An environment with no server or database configured reports "not configured" rather than
failing at query time. Local runs use the Azure CLI credential; a deployment uses its
assigned managed identity via `AZURE_CLIENT_ID`.

## Run locally

The API needs the embedding service running, since query vectors are computed per request:

```bash
cd ../embedding && uvicorn main:app --port 8081
```

Then, from this directory:

```bash
npm install
npm run build
npm start
```

Open `http://127.0.0.1:8000`. For development with hot reload, run `npm run dev:api` and
`npm run dev` in separate terminals and open the Vite URL.

## API

| Route | Purpose |
|---|---|
| `GET /api/readiness/:environment` | Whether a target is configured, reachable, and indexed |
| `POST /api/search` | `{ environment, mode, query }` returns evidence and timings |

## Commands

| Command | Purpose |
|---|---|
| `npm run build` | Typecheck server and client, build static assets |
| `npm run lint` | Run repository lint rules |
| `npm start` | Serve the built app and API on `127.0.0.1:8000` |

## Deployment

The app and the embedding service run as two containers in one Azure Container Apps
replica, so they communicate over loopback. Copy
[caldova-app.yaml.example](../deploy/caldova-app.yaml.example), replace every `REPLACE_*`
value, and keep the resulting environment-specific file out of Git.
