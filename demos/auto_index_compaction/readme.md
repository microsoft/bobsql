# Automatic Index Compaction (AIC) Demo

Demonstrates **Automatic Index Compaction** in Azure SQL Hyperscale — a background process that reclaims wasted space in indexes without rebuilds, maintenance windows, or downtime.

## What This Demo Shows

1. A clustered index with 1M rows at **99.8% page density** (baseline)
2. Scatter-delete 50% of rows → **47% density**, pages unchanged → scan reads double what's needed
3. Enable AIC → density recovers to **95%**, pages drop **51%**, scan elapsed drops **43%**

## Prerequisites

- **Azure SQL Hyperscale** database (AIC is a Hyperscale feature)
- A tool that can run T-SQL with `GO` batch separators (e.g., SSMS, Azure Data Studio, or [sqlsim](https://github.com/AzureSQLDemos/sqlsim))

## Test Configuration

| Setting | Value |
|---------|-------|
| Service Tier | Azure SQL Hyperscale |
| vCores | 8 |
| Scan | Single-threaded (`MAXDOP 1`), cold cache |
| Concurrency | None — each scan runs alone, no concurrent workload |

## Scripts

Run these in order. Use `scan-test.sql` between steps to measure cold-cache scan performance.

| Script | Purpose |
|--------|---------|
| **01-setup.sql** | Creates `dbo.aic_demo` with 1M rows (GUID clustered key, fixed-width `char(100)` rows), rebuilds to 99.8% density |
| **02-scan-test.sql** | Cold-cache `COUNT_BIG(*)` scan with `STATISTICS IO/TIME` — run after steps 01, 03, and 05 to compare |
| **03-degrade.sql** | Scatter-deletes 50% of rows via `CHECKSUM(id) % 2 = 0` — every page loses half its rows, no pages deallocated |
| **04-enable-aic.sql** | `ALTER DATABASE CURRENT SET AUTOMATIC_INDEX_COMPACTION = ON` |
| **05-check-progress.sql** | Monitors density, page count, fragmentation, and PVS size while AIC works |
| **06-cleanup.sql** | Drops the demo table and disables AIC |

## Demo Flow

```
01-setup.sql          →  02-scan-test.sql  (BASELINE: 17K pages, 463ms)
03-degrade.sql        →  02-scan-test.sql  (DEGRADED: 18K pages, 550ms)
04-enable-aic.sql     →  05-check-progress.sql  (watch density climb)
                      →  02-scan-test.sql  (AFTER AIC: 9K pages, 316ms)
06-cleanup.sql
```

## Expected Results

| Metric | Baseline | Degraded | After AIC |
|--------|----------|----------|-----------|
| Rows | 1,000,000 | 500,289 | 500,289 |
| Page Density | 99.8% | 47.1% | 95.0% |
| Pages | 16,953 | 18,004 | 8,909 |
| Logical Reads | 17,012 | 18,165 | 9,070 |
| Elapsed (cold) | 463 ms | 550 ms | 316 ms |

> **Why do pages increase after deleting rows?** In Hyperscale (ADR), every DELETE stamps a 14-byte version pointer on the ghost record. Pages at 99.8% density have almost no free space, so the version overhead causes some pages to split.

## Key Takeaways

- AIC compacted 18,004 half-empty pages into 8,909 well-packed pages — **no rebuild required**
- Logical reads dropped 50%, elapsed time dropped 43%
- Zero downtime, zero maintenance windows — AIC runs in the background
