# Ward General — `sqlsim` utilities

Load-simulation tooling for the **⚡ Scale it** demo: drive a realistic, **read-only**
workload at the `wardgeneral` Hyperscale database and produce a performance report,
so you can show the compute load that justifies scaling up.

---

> [!IMPORTANT]
> **`sqlsim` is a PREVIEW and is not publicly released yet.**
> The `sqlsim.exe` bundled here is provided **only** as a preview for this
> presentation. **Do not use it for any real production simulation or performance
> testing.** When the tool is released, the public GitHub repository will be at
> **<https://aka.ms/sqlsimtools>** — use that version for anything beyond this demo.

---

## What's here

```
utilities/sqlsim/
├─ sqlsim.exe              # PREVIEW workload simulator (see caveat above)
├─ sqlsim-usage.md         # full flag / parameter reference
├─ read-surge/             # the READ-ONLY "Scale it" workload
│  ├─ Run-ReadSurge.ps1    # driver (passwordless / Entra)
│  ├─ read-surge.json      # workload mix (census board / chart / worklist)
│  ├─ read-census-board.sql
│  ├─ read-patient-chart.sql
│  └─ read-worklist.sql
└─ reports/                # querystats → HTML report generators
   ├─ querystats-chart.ps1        # static HTML report from -querystats -json
   ├─ live-querystats-dashboard.ps1  # live auto-updating dashboard (Windows-auth only today)
   └─ chart.umd.min.js            # Chart.js (bundled for offline viewing)
```

## Prerequisites

- **ODBC Driver 18 for SQL Server** (the only runtime dependency).
- **`az login`** as an identity with access to `wardgeneral` — the driver
  authenticates passwordlessly with an Entra access token (no secrets).

## Run the read-only surge

From `utilities/sqlsim/read-surge/`:

```powershell
# 60-second surge (default), live per-query stats on the console
./Run-ReadSurge.ps1

# Shorter/longer run
./Run-ReadSurge.ps1 -DurationSeconds 10

# Surge AND build + open an interactive HTML performance report
./Run-ReadSurge.ps1 -DurationSeconds 10 -Report

# Point at a different server / database
./Run-ReadSurge.ps1 -Server <server>.database.windows.net -Database <db>
```

**Read-only by design** — every batch is a `SELECT` or a read stored procedure
(`ops.vBedCensus`, `clinical.GetPatientChart`, `clinical.SearchEncounters`). It
never inserts, updates, or deletes, so it is safe to run against the live demo
database. It deliberately loads the **primary** compute (no `ApplicationIntent=ReadOnly`)
so that scaling vCores is the answer.

## The performance report

`-Report` runs the surge with `-querystats -json -o read-surge-<timestamp>.json`,
then calls `reports/querystats-chart.ps1` to render and open
`read-surge-<timestamp>.html` — per-query **server CPU**, logical/physical reads,
throughput, and a details table.

**Before/after scaling:** run `-Report`, scale compute, run `-Report` again, and
compare the two HTML files — throughput up, CPU-per-query down.

For every `sqlsim` flag (threads, iterations, replay, JSON, encryption, etc.) see
[sqlsim-usage.md](sqlsim/sqlsim-usage.md).
