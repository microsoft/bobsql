# Benchmark — Versioning Throughput Comparison

Compares SQL Server throughput across four versioning configurations:

| Config | Settings |
|--------|----------|
| Baseline | READ COMMITTED (locking) |
| RCSI | READ_COMMITTED_SNAPSHOT ON |
| ADR+RCSI | Accelerated Database Recovery + RCSI |
| ADR+RCSI+OL | ADR + RCSI + Optimized Locking |

## Suites

### `inventory/` — Reader-Writer Contention

Mixed workload: 15 writer threads (order fulfillment, warehouse restock) + 25 reader threads (category reports, availability checks). Proves RCSI eliminates reader/writer blocking.

- `setup-inventory-all.ps1` — Creates 4 databases with 50K products × 20 categories
- `run-inventory-all.ps1` — Runs all 4 workloads via sqlsim

### `oltpstress/` — Pure DML

Write-only workload: 40 threads executing INSERT/UPDATE/DELETE with no readers. Isolates the overhead of version generation itself.

- `setup-stress-all.ps1` — Creates 4 databases with 50K rows each
- `run-stress-all.ps1` — Runs all 4 workloads via sqlsim

## Dependencies

- sqlsim.exe
- SQL Server 2025
