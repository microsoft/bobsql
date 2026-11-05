# SQL Server 2022 demos

These demos showcase SQL Server 2022 features and supporting deployment
scenarios. Choose one area and read its local README before running scripts.
Use the `sqlserver2022` workspace skill for guided selection.

## Collection map

| Area | Focus |
| --- | --- |
| [aad](aad/readme.md) | Microsoft Entra authentication |
| [azurearc](azurearc/readme.md) | Azure extension and connected SQL Server setup |
| [containedag](containedag/readme.md) | Contained availability groups |
| [containers](containers/readme.md) | Docker deployment and replication |
| [datavirt](datavirt/readme.md) | Data virtualization over Parquet and Delta |
| [IQP](IQP/readme.md) | Intelligent Query Processing feedback and optimization |
| [microsoftfabricsqlserver2022](microsoftfabricsqlserver2022/readme.md) | SQL Server and Fabric integration demonstrations |
| [milinkdr](milinkdr/readme.md) | Azure SQL Managed Instance link and disaster recovery |
| [purview](purview/readme.md) | Data governance integration |
| [s3objectstorage](s3objectstorage/readme.md) | S3-compatible backup and restore |
| [sql2022_hiddengems](sql2022_hiddengems/readme.md) | Less-visible engine and diagnostic features |
| [sqlk8s](sqlk8s/readme.md) | Kubernetes deployment and restart/failure labs |
| [sqlledger](sqlledger/readme.md) | Ledger |
| [synapselink](synapselink/readme.md) | Synapse Link |
| [tempdb](tempdb/readme.md) | tempdb concurrency |
| [tsql](tsql/readme.md) | T-SQL functions and surface area |

## Before running

Use SQL Server 2022 and the edition, compatibility level, sample database, and
tools required by the chosen area. Azure, Docker, Kubernetes, object storage,
and integration examples have additional prerequisites and can incur costs.
Legacy integrations may require service-specific updates.

Use a disposable lab. Inspect scripts for local paths, endpoints, authentication,
and cleanup before execution. Supply credentials using
[runtime inputs](../../SECRET-SCANNING.md#supplying-demo-credentials), including
SQLCMD mode where required by script headers. Scan binary data separately.

## Original feature notes

**azurearc**

Scripts to allow you to setup the SQL Server Extension for Azure feature in SQL Server 2022 setup.

**s3objectstorage**

Demo for backup and restore to S3 object storage in SQL Server 2022

**containedag**

Demo for Contained Availability Groups in SQL Server 2022

**datavirt**

Demo for polybase with S3 storage in SQL Server 2022

**IQP**

Demos for the nextgen of Intelligent Query Processing

**milinkdr**

Demos for the Link feature for Azure SQL Managed Instance for SQL Server 2022

**sqlledger**

Demos for SQL Ledger

**tempdb**

Demos for system page latch concurrency and tempdb
