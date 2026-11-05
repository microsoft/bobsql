# Example collections

Choose a collection below before installing dependencies or running scripts.
There is no shared application or universal setup command.

| Collection | Start here for |
| --- | --- |
| [adventureworks](adventureworks/readme.md) | AdventureWorksLT sample database import |
| [auto_index_compaction](auto_index_compaction/readme.md) | Azure SQL Hyperscale index compaction and measurement |
| [azuresqlai](azuresqlai/readme.md) | Azure SQL embeddings, approximate vector search, and RAG |
| [debugging_sql](debugging_sql/readme.md) | SQL Server process and query debugging with WinDbg |
| [insidetlog](insidetlog/readme.md) | Transaction log internals and recovery labs |
| [insidewaitslatchesspinlocks](insidewaitslatchesspinlocks/readme.md) | Wait, latch, spinlock, and log-rate investigations |
| [insidewaitslatchesspinlocks_workshop](insidewaitslatchesspinlocks_workshop/readme.md) | Numbered debugging and synchronization workshop |
| [polybase](polybase/readme.md) | SQL Server 2019 PolyBase fundamentals and external-source examples |
| [powerappssql](powerappssql/readme.md) | A Power Apps orders interface over Azure SQL |
| [securescaleabledbapp](securescaleabledbapp/readme.md) | Azure SQL application security, performance, and availability |
| [sqlbyexample](sqlbyexample/readme.md) | SQL Server 2019 capability walkthroughs |
| [sqllinux](sqllinux/readme.md) | SQL Server on Linux deployment, tuning, AG, and Docker demos |
| [sqlserver2022](sqlserver2022/readme.md) | SQL Server 2022 features and deployment scenarios |
| [sqlserver2025](sqlserver2025/readme.md) | SQL Server 2025 engine, developer, and AI capabilities |
| [sqlversioning](sqlversioning/README.md) | SQLBits 2026 row-versioning and ADR demonstrations |
| [wardgeneral](wardgeneral/readme.md) | The cumulative Ward General Hyperscale application |

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

Each collection has a matching [workspace skill](../.github/skills/) listed in
the [repository overview](../readme.md). Before publishing changes, follow
[Secret scanning](../SECRET-SCANNING.md).
