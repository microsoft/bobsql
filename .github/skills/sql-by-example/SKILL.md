---
name: sql-by-example
description: "Guide the SQL Server By Example collection: SQL Server 2019 ADR, containers, Kubernetes, PolyBase data-hub connectors, query processing, and lightweight profiling. Use when working with examples/sqlbyexample or choosing one of its bundled walkthroughs."
---

# SQL Server By Example

## Procedure

1. Read the [collection overview](../../../examples/sqlbyexample/readme.md)
   and select ADR, containers, the data hub, Kubernetes, or performance.
   Read the selected subfolder's README and actual scripts/notebooks.
2. Verify the historical SQL version/build, edition, sample database, tools,
   and connector requirements. Check current compatibility before using an old
   container tag, Kubernetes manifest, driver, or external service endpoint.
3. Inspect paths, targets, credentials, notebook outputs, and cleanup. Obtain
   approval before installing tools, provisioning resources, restoring data,
   changing configuration, or running stress/failure reproductions.
4. Execute the chosen walkthrough in numeric/session order on a disposable lab.
   Validate its specific result: recovery, container state, external joins,
   query-plan behavior, or live profiling evidence.
5. Distinguish captured notebook output from current measurements. Use synthetic
   data and privately supplied connection settings; inherited credential
   examples must not be published as working configuration.
6. Stop lab processes, close transactions, and follow the selected teardown
   with approval before removing databases, containers, or persistent storage.

This collection retains its own `sqlperf/iqp` material. It does not import the
separate `demos/sqlserver/iqp` collection. Follow
[secret checks](../../../SECRET-SCANNING.md) before publishing.
