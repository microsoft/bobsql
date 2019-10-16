# Intelligent Query Processing Examples

## Prequisites

1. Restore the WideWorldImportersDW database. This database requires about 4Gb+ disk space to restore.
2. Run the script **extendwwidw.sql** to make the db larger. It can take up to 15 minutes to run this and the db will now expand to **~25Gb** in size after this script completes.

## New Capabilities

In SQL Server 2019, we have created several new capabilities in addition to the features shipped under the name Adaptive Query Processing (AQP) in SQL Server 2017. If you want to see example for AQP in SQL Server 2017, visit this Github site: https://github.com/Microsoft/bobsql/tree/master/demos/sqlserver/aqp.

### Memory Grant Feedback for Row Store

### Table Variable Deferred Compilation

### Batch Mode for Row Store

### Scalar UDF Inlining

### Approximate Count Distinct