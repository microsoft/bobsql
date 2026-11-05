# tempdb troubleshooting

Evidence-first guides for investigating tempdb growth, space pressure, and
performance incidents. Confirm the database platform before selecting diagnostics.

| Scenario | Guide |
| --- | --- |
| tempdb data files or the log grow unexpectedly, with or without a slow workload | [Unexpected tempdb growth diagnostic kit](growth-and-slow-workloads/readme.md) |

The kit includes read-only SQL scripts and the workspace skill `tempdb-growth`
for SQL Server 2019+ and Azure SQL Managed Instance.

Begin with evidence collection, not shrinking files or restarting the database.
Use read-only diagnostics appropriate to the product/version, and keep production
data, query captures, and credentials out of this public repository.
