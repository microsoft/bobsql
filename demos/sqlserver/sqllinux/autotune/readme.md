This is a repro package to demonstrate the Automatic Tuning (Auto Plan Correction) in SQL Server 2017. This feature is using telemtry from the Query Store feature we launched with Azure SQL Database and SQL Server 2016 to provide built-in intelligence.

This repro is for SQL Server 2017 on Linux using feature of SQL Server Operations Studio result chart viewer because the Peformance Monitor Tool is not avaiable for Linux systems.

This demo assumes:

- You have SQL Server 2017 installed on Linux (requires Developer or Enteprise Edition)

- You have downloaded and installed SQL Server Operations Studio on your client. See https://docs.microsoft.com/en-us/sql/sql-operations-studio/download for more information. This demo assumes Jan 2018 version at minimum.

- You have downloaded the WideWorldImporters-Full.bak database from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak

In this demo, you will use SQL Operations Studio on your preferred platform to perform the demo to showcase automatic tuning (automatic plan correction). NOTE: To connect with SQL Ops Studio you may be connecting with an IP address. If so, be sure to use  <IP Address>:1433 to connect to SQL Server.

1. If you have not already done so, restore the WideWorldImporters database to your SQL Server 2017 instance. The WideWorldImporters-Full.bak is provided along with a restorewwi_linux.sql script to restore the database. Copy the .bak file to your Linux server into the /var/opt/mssql directory and run chown mssql:mssql WidwWorldImporters-Full.bak after copying.

2. Run the setup.sql script against the WideWorldImporters database. Close this when done.

3. Run the initalize.sql script to setup the repro for default of recommendations. If you need to restart the demo, you don't need to run setup.sql but you need to run initialize.sql. Close this when done.

4. Open up the following SQL Server script files. I recommend you open up each file one at a time.

- batchrequests_perf_collector.sql

- batchrequests.sql

- report.sql

- regression.sql

- recommendations.sql

5. Start the query in batchrequests_perf_collector.sql

6. Start the query in report.sql. Let this run for about 10-15 seconds to collect perf data

7. Run the query in batchrequests.sql. In the results window of SQL Ops Studio, pick Chart Viewer and change to Time Series type. This shows the "baseline of performance" for workload.

8. Run the query in regression.sql

9. Repeat the same steps as #7 and observe the performance degradation.

10. Observe the results in recommendations.sql. Notice the time difference under the reason column and value of state_transition_reason which should be AutomaticTuningOptionNotEnabled. This means we found a regression but are recommending it only, not automatically fixing it. The script column shows a query that could be used to fix the problem.

11. Open up and run auto_tune.sql. Close this when done

12. Cancel query in  batchrequests_perf_collector.sql. Start it again

13. Repeat steps 6-10. If the batch in report.sql is still running, cancel first, and start it again

In SQL Ops Studio Chart Viewer you will see the batch requests/sec dip but within a second go right back up. This is because SQL Server detected the regression and automatically reverted to "last known good" or the last known good query plan as found in the Query Store. Note in the output of recommendations.sql the state_transition_reason now says LastGoodPlanForced.
