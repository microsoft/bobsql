# Bug record — embedding run stalls after network loss (2026-07-23)

Captured from the overnight `generate-embeddings.ps1` run against `wardgeneral`
(`collierhealth-17`). The presenter lost internet connectivity mid-run; the run
did **not** self-recover after connectivity returned.

## What happened (timeline, from embeddings-progress.log / terminal)

| Time (local) | Event |
|---|---|
| 11:42 | Run started (batch = 2000). |
| 11:58 → 15:34 | Healthy: 2,000 → 26,000 embedded (~2,000 per ~18 min). |
| 15:49 | A batch **hung ~834 s then failed** (`Avg Elapsed: 834043.69 ms (0 successful, 1 failed)`, `Total Errors: 1`) — the outbound `AI_GENERATE_EMBEDDINGS` REST calls stalled when the connection dropped. |
| 15:49–15:56 | `az account get-access-token` failed: **`Failed to resolve 'login.microsoftonline.com'` (NameResolutionError / getaddrinfo failed)** → empty token → `sqlsim error: Access token cannot be empty (-T requires a value)`. |
| 16:14 | Briefly recovered — reached **28,000** (46.7%). |
| after 16:14 | **Stalled permanently at 28,000.** No further progress for 25+ min even though `az` could acquire a token again (verified len=2531). |

## Two suspected bugs

### 1. Driver (`generate-embeddings.ps1`) — does not survive a sustained outage
- `$token = (az account get-access-token ...)` is **not validated**. On an `az`
  failure the variable is empty (or contains error text), and the driver still
  calls `sqlsim -T $token` with an empty token → `Access token cannot be empty`.
- Those failed passes **count toward the 5-pass "no forward progress" ABORT**, so
  a network outage longer than ~5×15 s aborts the whole run — and it does **not**
  resume when connectivity returns.
- **Recommended fix:** validate the token is non-empty before invoking sqlsim; if
  empty/failed, loop-wait for connectivity with a longer backoff **without**
  incrementing the stall/abort counter; only count *real* embedding failures
  toward abort.

### 2. sqlsim / `AI_GENERATE_EMBEDDINGS` — batch hung ~834 s before failing
- A single 2,000-row batch's outbound embedding calls **hung ~14 minutes** before
  failing when the network dropped, rather than failing fast.
- **To file** (sqlsim preview — future repo <https://aka.ms/sqlsimtools>): a
  statement / HTTP timeout so a dropped connection fails fast instead of hanging.

## Resume (no data lost — resumable by design)
`clinical.ClinicalNoteEmbeddings` holds the 28,000 already done; re-running the
driver continues via `WHERE NOT EXISTS`:

```powershell
& 'C:\bwsql\presentations\hyperscale-developer\build\deploy\generate-embeddings.ps1'
```

Resumed 2026-07-23 from 28,000 / 60,000.
