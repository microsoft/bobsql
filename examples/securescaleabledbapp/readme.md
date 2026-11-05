# Demos for Azure SQL Database Security, Scalability, and Availability

These are demos for Azure SQL Database security, scalability, and availability. Each set of demos are in the following folders:

Use the `secure-scalable-db-app` workspace skill. Start with
[security](demo1_secure/readme.md), [performance](demo2_perf/readme.md), or
[availability](demo3_availability/readme.md). This collection supplies C# and
configuration snippets rather than a complete solution/project. Follow the
selected walkthrough's project requirements and use an isolated sample database.

The security example intentionally contrasts unsafe query construction with
parameterized access. Never expose the unsafe path or run its destructive
demonstration against real data. Supply credentials privately and obtain
approval before changing network access or triggering failover.

**demo1_secure**

Code and scripts to demonstrate Azure SQL Database secure connections and SQL Injection attacks.

**demo2_perf**

Scripts to show Parameter Plan Optimization (PSP) which is available in SQL Server 2022 Public Preview and will be available in Azure SQL Database.

**demo3_availability**

Code and scripts to show built-in retry logic in the SQL provider used against a failover for an Azure SQL Database.