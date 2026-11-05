# BobSQL

SQL Server and Azure SQL examples, book companion scripts, and hands-on
demonstrations. Start with a collection below, read its prerequisites, and use
a disposable lab environment. This repository is a catalog, not one application
with a shared build or deployment command.

## Examples

Each top-level example has its own Copilot skill. Open this repository as a
workspace in VS Code to discover the skills under [`.github/skills`](.github/skills/).
Ask for the named scenario or invoke the skill through the chat slash-command
menu. Skills guide the existing scripts; they do not automatically provision
resources or authorize destructive operations.

| Collection | What you can learn | Skill |
| --- | --- | --- |
| [AdventureWorks](examples/adventureworks/readme.md) | Import the AdventureWorksLT2025 sample BACPAC into Azure SQL | `adventureworks` |
| [Automatic index compaction](examples/auto_index_compaction/readme.md) | Observe page-density recovery in Azure SQL Hyperscale | `auto-index-compaction` |
| [Azure SQL AI](examples/azuresqlai/readme.md) | Managed-identity embeddings, vector search, and RAG from T-SQL | `azure-sql-ai` |
| [Debugging SQL Server](examples/debugging_sql/readme.md) | WinDbg, exceptions, hangs, query aborts, latches, spinlocks, and CPU | `debugging-sql` |
| [Inside the transaction log](examples/insidetlog/readme.md) | Physical log files, VLFs, log records, IO, recovery, and log management | `inside-transaction-log` |
| [Waits, latches, and spinlocks](examples/insidewaitslatchesspinlocks/readme.md) | Diagnose blocking, scheduling, synchronization, and log governance | `waits-latches-spinlocks` |
| [Waits, latches, and spinlocks workshop](examples/insidewaitslatchesspinlocks_workshop/readme.md) | Follow numbered modules from WinDbg basics through threadpool, latch, and spinlock investigations | `waits-latches-spinlocks-workshop` |
| [PolyBase](examples/polybase/readme.md) | Explore SQL Server 2019 external tables, execution diagnostics, and data-hub connectors | `polybase` |
| [Power Apps and SQL](examples/powerappssql/readme.md) | Build an orders canvas app backed by AdventureWorksLT | `powerapps-sql` |
| [Secure, scalable database application](examples/securescaleabledbapp/readme.md) | Azure SQL connectivity/security, PSP performance, and SqlClient retry/failover demonstrations | `secure-scalable-db-app` |
| [SQL Server By Example](examples/sqlbyexample/readme.md) | SQL Server 2019 recovery, containers, Kubernetes, data virtualization, and performance | `sql-by-example` |
| [SQL Server on Linux](examples/sqllinux/readme.md) | Installation/exploration, automatic tuning, cross-platform AGs, and Docker | `sql-linux` |
| [SQL Server 2022](examples/sqlserver2022/readme.md) | IQP, cloud integrations, containers, Kubernetes, ledger, data virtualization, and T-SQL | `sqlserver2022` |
| [SQL Server 2025](examples/sqlserver2025/readme.md) | AI, JSON, regex, REST, locking, resource governance, and ZavaHospital | `sqlserver2025` |
| [SQL versioning](examples/sqlversioning/README.md) | SQLBits 2026 multi-session RCSI, Snapshot, ADR/PVS, and optimized-locking demos | `sql-versioning` |
| [Ward General](examples/wardgeneral/readme.md) | A cumulative Hyperscale application spanning architecture, AI, security, resiliency, and performance | `wardgeneral` |

The [examples index](examples/readme.md) explains how to choose a starting point.
Nested folders contain local READMEs for navigation and their specific role.
Existing `README.md` and `readme.txt` walkthroughs are preserved; Markdown entry
points are supplied where only text instructions existed.

## Book companion material

Book scripts stay organized by chapter. Use the book's own prerequisites;
these older examples are not all interchangeable with current SQL releases.

| Folder | Coverage / starting point |
| --- | --- |
| [Azure SQL Revealed](books/azuresqlbook/README.MD) | Azure SQL performance, availability, and additional Azure features |
| [Azure SQL Revealed, second edition](books/azuresqlbook2/) | Placeholder for second-edition notes and errata |
| [SQL Server 2019 Revealed](books/sql2019book/README.MD) | Intelligent performance, security, availability, containers, Kubernetes, and virtualization |
| [SQL Server 2022 Revealed](books/sql2022book/readme.md) | Cloud connections, query intelligence, engine features, object storage, and T-SQL |
| [SQL Server 2025 book](books/sql2025book/readme.md) | AI fundamentals, AI features, developer features, Azure Arc, core engine, and Fabric mirroring |
| [SQL Server on Linux chapter scripts](books/sqllinuxbook/) | Chapter folders `ch3` through `ch11`; inspect the selected chapter before running |

## Repository layout

| Folder / document | Purpose |
| --- | --- |
| [`examples/`](examples/readme.md) | Runnable demos, supporting source, and captured example results |
| [`books/`](books/) | Book-specific chapter material |
| [`troubleshoot/`](troubleshoot/) | Troubleshooting guides, starting with [tempdb](troubleshoot/tempdb/readme.md) and a warehouse pipeline upsert timeout scenario |
| [`.github/skills/`](.github/skills/) | One workspace skill per top-level example |
| [`scripts/`](scripts/) and [`.githooks/`](.githooks/) | Local secret-check setup and commit/push guards |
| [Secret scanning](SECRET-SCANNING.md) | Installation, checks, regression tests, and limitations |

## Before running a demo

1. Select the collection and read its README, then the specific subfolder's
   instructions. There is no repository-wide dependency installation step.
2. Verify the required SQL version, edition, database compatibility level,
   sample database, and tools. Requirements vary: SSMS/sqlcmd, PowerShell,
   Azure CLI, Docker, Kubernetes, .NET, or Python may be needed.
3. Use a disposable database or lab instance. Some examples restart SQL Server,
   attach a debugger, generate heavy load, delete data, change configuration,
   restore databases, or deliberately trigger failures.
4. Review target names and local paths. Old scripts may contain author-specific
   endpoints, legacy commands, or sample credentials. Supply your own values
   privately; never reuse demo credentials in production.
5. Approve billable Azure resources and disruptive changes before executing.
   Record the starting state and follow the selected demo's cleanup procedure.

Example paths in this repository begin with `examples`, not the original
private repository's `demos` directory. Some inherited walkthroughs also refer
to external figures or optional skills that are not bundled here; check paths
against the files actually present.

## Before committing or pushing

Install Gitleaks and enable the checkout's guards:

```powershell
winget install --id Gitleaks.Gitleaks --exact
& .\scripts\install-secret-hooks.ps1
```

Follow [Secret scanning](SECRET-SCANNING.md) before publishing any copied
content. A passing scan is not permission to publish private data or a guarantee
that a binary database package is safe. Local hooks must be installed per clone
and can be bypassed; use GitHub push protection as an additional control.

## Maintaining this catalog

When adding an example, include prerequisites, the entry point, execution order,
expected observations, and cleanup. Give every example source directory a
Markdown README, including supporting-data and result folders; do not document
generated `bin`, `obj`, or dependency-cache directories as source. Add or update
the corresponding workspace skill and the example catalog. Keep real secrets
and private datasets out of both scripts and documentation.
