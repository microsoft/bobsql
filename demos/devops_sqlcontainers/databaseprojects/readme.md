# Demo for building and publishing a database project using a local SQL Server container

This is a demo for building and publishing a database project using a local SQL Server container.

## Setup

You can perform these demos on Windows, Mac, or Linux.

- Install Visual Studio Code
- In VS Code, use the Extensions option on the left-hand menu. Search for the SQL Database Projects extension and install it. It will also install the SQL Server (mssql) extension.
- Install Docker if you do not have it already installed.
- Copy the *.sql files from <https://github.com/microsoft/bobsql/tree/master/demos/devops_sqlcontainers/databaseprojects> (or if you have cloned the repo) into a local folder. For the purposes of these instructions I use the **c:\database_projects\bwsql** folder.

## Create a new database project

1. Select the **Database Projects** option in the left-hand menu in VS Code.
1. Select **Create New**
1. Select **SQL Server Database**
1. Enter in project name **bwdb**
1. Put in your folder name for files. I used **c:\database_projects\bwsql**
1. Select **SQL Server 2022**
1. Select **No**
1. Select Yes to Trust message
1. Your new Database Project should show up in the list.

## Add objects to the database

Since we have built a series of T-SQL scripts to add a table, index, stored procedure, and populate data, let's add them to the project so it can be built.

1. Right-click on the database name **bwdb** and select **Add Existing Item...** Select the **customers.sql** file.
1. Repeat this for **createindex.sql** and **get_customerbyid.sql**
1. We want to populate data after the objects have been created. Right-click on the database name bwdb and select **Add Post-deployment script**. Give it a name of **data**. Copy the T-SQL code from populate_data.sql into this script window.
1. Your Database References should now show scripts for createindex.sql, customers.sql, data.sql, and getcustomer_byid.sql

## Build the database project

1. Right-click the database name bwdb and select **Build**.
1. Your output window in VSCode shows the progress of the build which is to use the Microsoft.Build.SQL SDK to build a SQL project in the form of a .sqlproj file.

## Publish the project to a local SQL Server container

1. Right-click the database name bwdb and select Publish
1. Select **Publish to new SQL Server local development container**
1. Type in port 1500 to avoid any conflicts with other containers or SQL instances
1. Type in a password for the sa login.
1. Select **Microsoft SQL Server**
1. Select Yes to accept the EULA
1. Select **2022-latest** for the container image.
1. Select **Don't use profile**
1. Select **bwdb New**
1. The output pane will show a docker image being pulled if it does not exist and a SQL container being run. Then a brief connection test will be done (it could take a few attempts).
1. Then the output shows a DACPAC being built and deployed to the container.

## Connect to the database and run a query

1. If everything is successful you will see in VS Code a new SQL connection already setup for your local SQL container
1. Expand tables to see the Customer table.
1. Expand the customer table to see the index.
1. Expand programmability to see the stored procedure
1. Right-click on the connection and select **New Query**
1. Type in the following T-SQL code and click on the Green play button on the right.

```sql
SELECT COUNT(*) FROM customers;
```

Your results should be in a new window and show a count of 1503076. Close the results and query window.

## Analyze a performance problem with the database

## Make a change in the database to fix the problem and perform a validation
