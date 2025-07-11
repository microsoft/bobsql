# Performance in SQL Server 2025

This folder contains instructions and scripts to demonstrate the new features of SQL Server 2025 for performance. The demos are designed to be run on a SQL Server 2025 instance.

## Prerequisites

Unless stated otherwise, the minimum prerequisites can be found in the [SQL Server 2025 Engine Demos](../readme.md) readme.

Each demo may have additional prerequisites. Please check the specific demo readme for details.

## References

Find out more about SQL Server 2025 at https://aka.ms/sqlserver2025docs.

## Demos

The following demos are included in this folder. Stay tuned for more demos to be added in the future. 

**Optimized Locking**

This feature is designed to improve the performance of concurrent transactions by reducing contention on locks.

**ABORT_QUERY_EXECUTION hint**

This feature is used to mark a query that may be causing major system performance issues to automatically be aborted on its next and subsequent executions.

**Optimized sp_executesql**

This feature allows you to optimize the performance of sp_executesql by reusing the plan for the statement or batch through preventing multiple copies of the same query plan to be cached. This can reduce memory pressure and improve performance.

**Tempdb space resource governance**

This feature allows you to manage the resources used by tempdb by configuring the Resource Governor to limit the space used by tempdb for users both for explicit temporary tables or internal space used for operations like sorts.

