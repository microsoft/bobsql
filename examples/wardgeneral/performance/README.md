# Performance — Scale and Tune Ward General

Performance continues the same Ward General system built in Areas 2 through
9. It does not deploy a replacement database or introduce a disconnected
benchmark. The reader increases load on the existing application, scales its
compute, grows its existing clinical data, tunes the structures that became
large, and reviews how the existing vector-search path uses a named replica.

## The progression

| Stage | Reader action | What carries forward |
| --- | --- | --- |
| [1. Scale compute](01-scale-compute/) | Run the same Getting Started procedure workload at `HS_Gen5_8`, `HS_Gen5_16`, and `HS_Gen5_40` through one approval-gated orchestration. | Architecture explains why no data moves. Observability supplies the measurements. High Availability and Resiliency already established the separate cutover/retry behavior. |
| [2. Grow data and find the constraint](02-grow-data/) | Drive 64 concurrent writers for five minutes, show automatic 10 GB storage allocation, and measure the write path. Repeat the interval when more data is useful. | The database, schema, security posture, application, and Standard-series hardware remain unchanged. Only data volume changes. |
| [3. Tune Ward General](03-tune-grown-data/) | Run independent JSON-index and memory grant feedback demonstrations with bounded, demo-owned clinical data. | Observability's plan and runtime evidence remain the measurement model; these examples do not depend on stage 2 growth. |

Each stage has its own repository skill. Use `scale-and-tune-wardgeneral` only
for the complete three-stage progression; use the owning skill named in the
stage README for an individual demo.

The sequence changes one governing constraint at a time:

1. Scale **up** when active work needs more CPU, memory, or workers.
2. Grow **data** and use the evidence to identify the governing constraint.
3. **Tune** access paths after the data has grown.

The documentation separately revisits the AI-Ready SQL Research page to explain how
`wardgeneral-research` isolates vector-search compute and how additional named
replicas can provide more aggregate read capacity. That review is conceptual,
not a fourth runnable example.

## What the reader already has

- The `wardgeneral` Hyperscale database, schema, seed data, procedures, HA
  configuration, and `wardgeneral-research` named replica from Getting Started.
- The page-server, log-service, RBPEX, and replica model from Architecture.
- The Ward General application, passwordless connection factory, connection
  pooling, and retry policy from Ward General App.
- Native JSON, embeddings, DiskANN, and `clinical.SearchSimilarNotes` from
  AI-Ready SQL.
- The agentic workflow and its connection-density motivation from Agentic AI.
- Query Store, waits, DMVs, Azure Monitor, and Extended Events from Observability.
- The Security security posture, including row-level security when enabled.
- The High Availability and Resiliency evidence that a compute cutover can reset a connection and that
  the application must tolerate it.

## Reader-run exercises

All three stages are reader-run exercises. Each Stage 2 execution runs one
five-minute write interval and reports the growth that actually occurred.
Readers can repeat it when they want more data.

Every Azure compute change is preview-first. A script must print the current
and requested configuration and require explicit approval before changing a
billable resource.

## Current build status

| Stage | Status |
| --- | --- |
| 1 | Orchestrated `HS_Gen5_8 → HS_Gen5_16 → HS_Gen5_40` progression, with one explicit approval covering both displayed scale changes, passwordless `sqlsim` load at each size, and focused measurements. |
| 2 | **Complete.** Live-validated on `wardgeneral` at `HS_Gen5_40`: one five-minute interval added 12.065 GB, grew allocated data files automatically from 20 GB to 40 GB, reached 70.35 MiB/s peak actual log throughput, and completed 687 transactions without failure. |
| 3 | JSON-index path complete: 5,000,005-row live validation reduced logical reads from 162,050 to 24. Query-feedback path complete: in the canonical run, MGF eliminated a 390.50 MB spill and cut elapsed time by 52% on execution 2; CE feedback did not intervene. Both paths have verified cleanup; Observation tuning remains deferred. |

## Sources

- [Microsoft Learn — Hyperscale secondary replicas](https://learn.microsoft.com/azure/azure-sql/database/service-tier-hyperscale-replicas), accessed 2026-09-11.
- [Microsoft Learn — Intelligent Query Processing](https://learn.microsoft.com/sql/relational-databases/performance/intelligent-query-processing), accessed 2026-09-11.
- [Microsoft Learn — `CREATE JSON INDEX`](https://learn.microsoft.com/sql/t-sql/statements/create-json-index-transact-sql), accessed 2026-09-11. The reference still labels this feature preview and lists SQL Server 2025; re-verify Azure SQL Database documentation before documentation freeze.
