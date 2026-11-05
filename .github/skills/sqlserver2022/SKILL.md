---
name: sqlserver2022
description: "Select and run SQL Server 2022 feature demos: IQP, Azure Arc, Entra authentication, contained AGs, MI link, Fabric/Synapse integration, ledger, S3, Parquet/Delta, containers, Kubernetes, tempdb, and T-SQL. Use for examples/sqlserver2022."
---

# SQL Server 2022 demonstration collection

## Procedure

1. Read the [collection catalog](../../../examples/sqlserver2022/readme.md)
   and select one area. Use its local README and actual files, not a guessed
   script order or an obsolete folder name.
2. Verify SQL Server 2022 edition/build, compatibility level, sample database,
   permissions, and client tools. For integrations, independently verify
   current Azure/service support, accounts, storage, and network prerequisites.
3. Inspect scripts/manifests for endpoints, paths, and private configuration.
   Supply runtime credentials following [secret setup](../../../SECRET-SCANNING.md#supplying-demo-credentials),
   including SQLCMD mode where script headers require it. Never suppress findings.
4. Present the target and operational impact. Require approval before creating
   Azure resources, exposing services, changing identity/HA configuration,
   restoring data, applying Kubernetes manifests, or generating heavy load.
5. Run the selected walkthrough in its numeric/session order. Validate actual
   plans, feedback, data access, container/pod state, or integration evidence
   relevant to that demo. Treat captured examples as illustrative, not expected
   measurements.
6. Follow the area's teardown and verify its scope before deleting cloud
   resources, databases, containers, volumes, or persistent storage.

## Boundaries

This collection has no universal build. Kubernetes restart labs do not establish
an availability-group guarantee. Parquet/Delta files are supporting data, not
code; preserve metadata and inspect publication suitability separately.
Follow [secret checks](../../../SECRET-SCANNING.md).
