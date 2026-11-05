This folder contains demos for SQL Server on Linux. These are freely available to use by the public

## Local walkthroughs

- [Automatic tuning](autotune/readme.md)
- [Cross-platform availability groups](demo_cross_platform_ags/readme.md)
- [Explore SQL Server on Linux](demo_explore_sql_linux/readme.md)
- [SQL Server in Docker](demo_sql_docker/readme.md)
- [Deploy and explore](deploy_and_explore/readme.md)

Use the `sql-linux` workspace skill. These are historical SQL Server 2017-era
examples, not current package-installation guidance. Verify distribution and
SQL version support, inspect local paths and authentication, and use an isolated
lab. Obtain approval before package/service or availability-group changes.
Supply runtime credentials using [secret setup](../../SECRET-SCANNING.md#supplying-demo-credentials).

Autotune - This is a demo showing the Automatic Tuning feature of SQL Server 2017 using Linux

demo_explore_sql_linux - This is a series of instructions I usually use to show how to install SQL Server on Linux and explore what is installed

demo_cross_platform_ags - This is a demo I usually use to show how to setup and configure a cross-platform Availability Group between SQL Server on Windows and Linux

demo_sql_docker - This is a demo I usually use to show the deployment and capabilities of SQL Server on Linux in a Docker Container