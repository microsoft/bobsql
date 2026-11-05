---
name: polybase
description: "Guide the dedicated SQL Server 2019 PolyBase fundamentals and WideWorldImporters data-hub demos. Use when working with examples/polybase, head/compute-node diagnostics, external-table execution, or its SQL Server, Azure SQL, HDFS, Oracle, Cosmos DB, and SAP HANA connectors."
---

# PolyBase fundamentals and data hub

## Procedure

1. Read the [collection README](../../../examples/polybase/readme.md),
   then the fundamentals or chosen data-hub connector walkthrough.
2. Verify the actual SQL Server version/build, PolyBase installation/services,
   supported connector/driver, remote source, and WideWorldImporters lab data.
   These examples reference SQL Server 2019 previews and scale-out/Hadoop
   features; do not assume they work unchanged on later releases.
3. Inspect scripts for node names, endpoints, filesystem paths, credentials,
   and required permissions. Supply secrets privately and review notebook
   outputs; do not reuse or allowlist inherited literal credentials.
4. Obtain approval before restarts, firewall changes, scale-out setup,
   external-source configuration, database writes, or billable resources.
   Keep the target source and SQL lab isolated.
5. Run the selected setup and external-table queries, then verify the remote
   data and local joins. For fundamentals, use the supplied status and execution
   diagnostics to observe actual node/query behavior.
6. Report unsupported prerequisites or connection errors explicitly. Follow
   the connector's cleanup for lab-owned credentials, data sources, formats,
   and external tables without deleting remote source data automatically.

Follow [secret checks](../../../SECRET-SCANNING.md) before publication. This
dedicated collection is distinct from the similar `sqlbyexample/sqldatahub` demos.
