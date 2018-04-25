These are demos to show how to deploy SQL Server and explore basic features and the installation

In order to run theses demo, first follow these instructions

- Copy the WideWorldImportersSample database from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak. Copy this file on your Linux Server VM in your home directory. Use a program like winscp or scp to copy the file. (I use the drag and drop feature of MobaXterm for files of small sizes like this)
- Copy all the .sh and .sql files in this directory to your home directory on Linux. Execute chmod +x *.sh

Deploying SQL Server for RHEL. This demo assumes a reasonable, reliable Internet connection

1. Download the repo file with this command

sudo curl -o /etc/yum.repos.d/mssql-server.repo https://packages.microsoft.com/config/rhel/7/mssql-server-2017.repo

2. Install SQL Server using yum

sudo yum install -y mssql-server

3. Complete the installation with mssql-conf. Choose your edition, accept the EULA, and supply a system administrator (sa) password

sudo /opt/mssql/bin/mssql-conf setup

4. Confirm SQL Server is running

sudo systemctl status mssql-server

Show how there are two SQL Server processes. The top one is the "parent watchdog" process and the second one is the true SQL Server Engine.

5. Explore the SQL Server installation

What does the ERRORLOG say?

sudo more /var/opt/mssql/log/errorlog

Where are the ERRORLOG and other log files located?

sudo ls /var/opt/mssql/log

Where are the database and transaction log files?

sudo ls /var/opt/mssql/data

Where are the SQL Server binary files stored?

sudo ls /opt/mssql/bin

6. Add a login and restore a database

- Execute supplied addlogin.sh to add a new login to use an account other than sa. Modify the addlogin.sql script to use the password of your choosing. When prompted supply the sa password you used when installing SQL Server
- Execute the supplied cpwwi.sh to copy the WideWorldImporters to your data directory
- Execute the supplied restorewwi.sh to restore the database. When prompted, use the password for the sqllinux login from the addlogin.sql script. This may take a minute or so to execute

7. Run queries with our tools

- Use sqlcmd to query sys.databases and the WWI database

sqlcmd -Usqllinux -P<your password from addlogin.sql>

> SELECT * FROM sys.databases

> GO

..[ Results will show up here ]

> USE WideWorldImporters

> GO

..[ Results will show up here ]

> SELECT * FROM [Application].[People]

> GO

..[ Results will show up here ]

> EXIT

- Use mssql-cli to run the same queries. mssql-cli does not have a -P parameter so you will be prompted for the password. Notice how Intellisense works and the output of the queries are in a vertical format so it is easier to read each row
- Use SQL Operations Studio to connect to your SQL Server on Linux. Look at Object Explorer, Server Extensions, and run Queries
- If you installed SSMS, connect to your Linux Server and explore the basic features of running queries and Object Explorer. Use the XEProfiler to trace queries.