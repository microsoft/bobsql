# Example collections

Choose a collection below before installing dependencies or running scripts.
There is no shared application or universal setup command.

| Collection | Start here for |
| --- | --- |
| [adventureworks](adventureworks/readme.md) | AdventureWorksLT sample database import |
| [auto_index_compaction](auto_index_compaction/readme.md) | Azure SQL Hyperscale index compaction and measurement |
| [azuresqlai](azuresqlai/readme.md) | Azure SQL embeddings, approximate vector search, and RAG |
| [caldovaevidenceagent](caldovaevidenceagent/README.md) | Hyperscale native embeddings and DiskANN search with governed SQL MCP tools and a Microsoft Foundry hosted evidence agent |
| [caldovaresearch](caldovaresearch/README.md) | Hyperscale evidence search from a serverless pilot to a one-million-row vector-search target and named replicas |
| [debugging_sql](debugging_sql/readme.md) | SQL Server process and query debugging with WinDbg |
| [handsfreeindexing](handsfreeindexing/README.md) | Hyperscale automatic index creation and Automatic Index Compaction with live query and index-health measurements |
| [insidetlog](insidetlog/readme.md) | Transaction log internals and recovery labs |
| [insidewaitslatchesspinlocks](insidewaitslatchesspinlocks/readme.md) | Wait, latch, spinlock, and log-rate investigations |
| [insidewaitslatchesspinlocks_workshop](insidewaitslatchesspinlocks_workshop/readme.md) | Numbered debugging and synchronization workshop |
| [polybase](polybase/readme.md) | SQL Server 2019 PolyBase fundamentals and external-source examples |
| [powerappssql](powerappssql/readme.md) | A Power Apps orders interface over Azure SQL |
| [securescaleabledbapp](securescaleabledbapp/readme.md) | Azure SQL application security, performance, and availability |
| [sqlbyexample](sqlbyexample/readme.md) | SQL Server 2019 capability walkthroughs |
| [sqllinux](sqllinux/readme.md) | SQL Server on Linux deployment, tuning, AG, and Docker demos |
| [sqllocal](sqllocal/README.md) | SQL Server 2025, Foundry Local, and the synthetic Caldova transfer-center demo |
| [sqlserver2022](sqlserver2022/readme.md) | SQL Server 2022 features and deployment scenarios |
| [sqlserver2025](sqlserver2025/readme.md) | SQL Server 2025 engine, developer, and AI capabilities |
| [sqlversioning](sqlversioning/README.md) | SQLBits 2026 row-versioning and ADR demonstrations |
| [startandgrowhyperscale](startandgrowhyperscale/README.md) | A Hyperscale scheduling app that grows from serverless to an elastic pool with native cross-database queries |
| [wardgeneral](wardgeneral/readme.md) | The cumulative Ward General Hyperscale application |

The four Caldova Hyperscale examples are independent collections with their own
prerequisites and deployment instructions. Automatic Index Compaction requires
preview access. The Start and Grow README distinguishes live operations from opt-in
presentation illustrations. For the evidence-search corpora, see
[third-party notices](THIRD-PARTY-NOTICES.md) for CC BY attribution and licensing.

## Running safely

- Read the collection and subfolder README first. Match the SQL version and
  prerequisites rather than assuming every script runs on the same instance.
- Use isolated lab resources. Debugging and recovery demos can stop SQL Server;
  performance and contention demos can exhaust CPU, storage, or connections.
- Review placeholders, paths, credentials, resource names, and cleanup.
  Supply secrets privately and obtain approval before billable or destructive work.
- Captured results are illustrative evidence from previous runs, not performance
  guarantees. Source folders have Markdown READMEs; generated build output is
  not part of this documentation coverage.

Existing [workspace skills](../.github/skills/) are described in
the [repository overview](../readme.md). For the new Caldova collections, start
with their linked READMEs and runbooks. Before publishing changes, follow
[Secret scanning](../SECRET-SCANNING.md).
