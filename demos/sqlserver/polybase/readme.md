# SQL Server 2019 Polybase Demos

These are demos to show the capabilities of Polybase in SQL Server 2019 (independent of Big Data Clusters)

The demos are organized into the following folders

## fundamentals

Use these demos to show basics of Polybase head and compute nodes and the execution lifecycle of an external table to HDFS files. Yout must go through this demo to setup Polybase to be able to run the demos in the sqldatahub folder, unless you already have a SQL Server 2019 CTP 2.3 or higher Polybase cluster.

## sqldatahub

These demos show an example of using the WideWorldImporters database as a hub in SQL Server but connected to related data in other sources such as

- SQL Server 2008R2
- Azure SQL Database
- HDFS
- Oracle
- CosmosDB
- SAP HANA

**Note: These demos all require you to setup Polybase on SQL Server 2019 CTP 2.3 or higher with all of the steps from the Fundamentals folder.**