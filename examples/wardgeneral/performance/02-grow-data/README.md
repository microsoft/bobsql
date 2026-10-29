# Stage 2 — Grow Data and Find the Constraint

**Owning skill:** `grow-wardgeneral-database`

Prompt: **Run Performance Demo 2: drive Ward General writes for five minutes and
identify the constraint from the measured evidence.**

Continue with the database scaled in stage 1. Add realistic numeric, JSON, and
free-text clinical history while measuring database growth, generated log,
resource use, waits, and Hyperscale log-governance evidence.

Each execution runs one 300-second sqlsim interval and reports the database
growth that actually occurred. Readers can rerun the same workload when they
want more data. The exercise remains on `HS_Gen5_40`; it does not move the
database to Premium-series.

`growth-workload.json` drives 64 concurrent writers across:

- `clinical.Observation` for numeric telemetry;
- `clinical.LabResult` for native JSON laboratory panels; and
- `clinical.ClinicalNote` for free text.

This stage does not create another database. Its enlarged tables remain part
of Ward General, while the implemented stage 3 examples use independent,
bounded fixtures so either tuning sequence can be run on its own.

## What runs

| File | Purpose |
| --- | --- |
| `run-demo.ps1` | Previews the exact target, then orchestrates one workload interval, monitoring, final capture, and reporting with `-Execute`. |
| `growth-workload.json` and `sql/` | Run the 64-writer numeric, JSON, and free-text workload for 300 seconds. |
| `capture-growth-io.sql` | Captures structured before/after allocation, table, virtual-file I/O, wait, and resource evidence. |
| `sample-growth-io.sql` | Captures a lightweight performance and growth point every 15 seconds on a separate connection. |
| `build-growth-report.ps1` | Produces `summary.json`, `growth-timeline.csv`, and `performance-report.html`. |

## Run it

Preview the target, current reserved size, and five-minute workload. This
connects read-only and does not start the workload:

```powershell
./run-demo.ps1
```

After reviewing the preview, run the growth exercise:

```powershell
./run-demo.ps1 -Execute
```

The runner requires the `HS_Gen5_40` state left by Demo 1. It launches sqlsim
with `growth-workload.json` and samples the database from a separate connection
every 15 seconds. The reader does not need a second terminal.

Every run is retained beneath `results/runs/<UTC-run-id>/`. The directory is
gitignored and contains raw workload output, before/after snapshots, individual
timeline samples, run metadata, and the three report formats.

The HTML report shows:

- a line chart showing reserved size rising while allocated data-file size
  steps across the platform-managed 10 GB growth boundary;
- a post-chart wait panel that calls out `RBIO_RG_*` wait types, task count,
  total duration, the dominant measured wait, and `WRITELOG` duration;
- starting size, ending size, total growth, elapsed time, and GB/hour;
- actual peak and average log throughput in MiB/s;
- average log write latency;
- CPU, data I/O, log utilization, and cumulative log bytes over time;
- workload completion status and whether log governance appeared.

The workload is append-only. Repeating the command adds another five-minute
growth interval; the runner never deletes generated clinical history or
shrinks files.

## Calibration result

The workload was calibrated on a disposable PITR copy at `HS_Gen5_40` with 64
zero-think writers: 32 numeric, 24 JSON, and 8 free-text. Each
transaction targets approximately one quarter of the encounter population so
the workload remains sustained without leaving oversized transactions to time
out after the scheduling window. The final end-to-end test completed 428
transactions without failure and added 3.763 GB in 2.49 minutes. Peak 15-second
average log-write utilization was 75.90 percent, with no `RBIO_RG_*` waits.
CPU peaked at 19.89 percent.

The canonical five-minute run on `wardgeneral` added 12.065 GB, completed 687
transactions without failure, and grew allocated data files automatically from
20 GB to 40 GB in two 10 GB steps. Actual log throughput peaked at 70.35 MiB/s
and average log write latency was 2.427 ms.

That result is the lesson: even an intentionally aggressive ingestion workload
did not reach the Standard-series log-rate boundary. The exercise must report
the measured constraint rather than assume log governance. Premium-series is a
separate design option for workloads whose evidence shows that they actually
reach the Standard-series boundary; it is not a step in this demo.
