Note: This demo comes directory from one published by Joe Sack, PM at Microsoft for the AQP feature. Refer to this link for the original demo files and instructions:

https://github.com/joesackmsft/Conferences/blob/master/Data_AMP_Detroit_2017/Demos/AQP_Demo_ReadMe.md

Here are the instructions for demonstrating Adaptive Query Processing in SQL Server 

1. If not already provided, download the WideWorldImportersDW-Full.bak from https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0

2. Restore the database to your SQL Server 2017 instance. A sample script is provided: restore_wwidw.sql

3. Create the Multi-Statement Table Valued Function [Fact].[WhatIfOutlierEventQuantity] from the script WhatIfOutlierEventQuantity.sql

4. Run through the three demo scenarios by following the comments and T-SQL commands in AQP_AMP_Demos.sql

Note: I've provided separate scripts for each scenario if you would like to run these separately.
