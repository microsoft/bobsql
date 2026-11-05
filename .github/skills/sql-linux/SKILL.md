---
name: sql-linux
description: "Guide the SQL Server on Linux collection: install/explore SQL Server 2017, automatic tuning, cross-platform availability groups, and Docker demonstrations. Use when working with examples/sqllinux and its Linux shell, SQL, and Windows Docker helper scripts."
---

# SQL Server on Linux

## Procedure

1. Read the [collection README](../../../examples/sqllinux/readme.md) and
   the selected installation, exploration, automatic-tuning, availability-group,
   or Docker walkthrough.
2. Verify Linux distribution, SQL version/build, tools, sample database, and
   permissions. The inherited instructions reference SQL Server 2017 and older
   distribution/package URLs; check supported combinations before installation.
3. Inspect hostnames, file paths, service commands, credentials, certificates,
   and container settings. Distinguish commands for Linux from Windows `.cmd`
   helpers; do not run Linux service/package commands on the Windows host.
4. Obtain approval before package changes, service restarts, restoring data,
   certificate/login creation, availability-group changes, container deployment,
   or workload generation. Use a disposable lab and private credentials.
5. Follow the selected sequence, verifying service state, SQL connectivity,
   plans/tuning recommendations, container state, or replica behavior as
   appropriate. Do not turn old screenshots or example paths into assumed facts.
6. Stop workloads and follow the area-specific cleanup. Preserve original
   settings and confirm scope before removing databases, certificates,
   containers, or volumes.

Follow [secret checks and runtime credential setup](../../../SECRET-SCANNING.md).
Review database/certificate assets separately before publication.
