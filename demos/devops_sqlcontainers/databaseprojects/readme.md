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

You have been told there is a performance problem with the stored procedure in the database and need to analyze why.

1. Execute the procedure using an option to look at query plan details. Use the VSCode File, Open File to open up the provided script **execproc_withplan.sql**. Click the play button. You will see a choice of connection profiles. Choose the one that says **sqldbproject-bwdb....**

In the results window the first result is to extract rows from the table.

The second result is detailed of the query plan. The 3rd row in the **StmtText** column shows "...Table Scan". This means the index that was created by customer_id is not being used.

1. Dive into more details on why the index is not used by opening up the script **marksurenowarnings.sql**. Execute the query. Choose the same connection profile. You should see a new result with a XML value. Click on the XML value. A new window should appear with a result like the following:

```xml
<p1:Warnings 
  xmlns:p1="http://schemas.microsoft.com/sqlserver/2004/07/showplan">
  <p1:PlanAffectingConvert ConvertIssue="Cardinality Estimate" Expression="CONVERT_IMPLICIT(int,[bwdb].[dbo].[customers].[customer_id],0)" />
  <p1:PlanAffectingConvert ConvertIssue="Seek Plan" Expression="CONVERT_IMPLICIT(int,[bwdb].[dbo].[customers].[customer_id],0)=[@customer_id]" />
</p1:Warnings>
```
This warning indicates that an index could not be used due to a conversion problem.

1. Go back to the database project and look at the definition of the procedure getcustomer_byid in the file getcustomer_byid.sql Notice the parameter passed in to the procedure is an **int** type
1. Look now at the table definition in the customers.sql. Notice the customer_id is defined as a nvarchar(10) type. This the reason for the conversion problem.

## Make a change in the database to fix the problem and perform a validation

We need to change the procedure but we only want the procedure change to get applied to the currently running container.  We can use the power of database projects to make a change, run a new build, and publish the changes to the running container.

1. In the database project, edit the **getcustomer_byid.sql** script and change the parameter to use nvarchar(10) like the following:

```sql
CREATE PROCEDURE [dbo].[getcustomer_byid]
  @customer_id nvarchar(10)
AS
  SELECT * FROM customers WHERE customer_id = @customer_id;
RETURN 0
```
1. Save the changes
1. Right-click the database name and select **Build**
1. Now our database project has the changes let's publish this to the running container
1. Right-click the database and select **Publish**
1. Select **Publish to an existing SQL Server**
1. Select **Don't use profile**
1. Choose **sqldbproject-bwdb....**
1. Select **bwdb**
1. Select **Publish**. You will see a message **Deploy dacpac: In Progress** and then **Deploy dacpac: Succeeded. Completed.**

## Verify the performance problem is resolved

1. Click on the SQL Server icon in the left-hand menu of VS Code. Your connection for the local container should be listed.
1. Execute the procedure using an option to look at query plan details. Use the VSCode File, Open File to open up the provided script **execproc_withplan.sql**. Click the play button. You will see a choice of connection profiles. Choose the one that says **sqldbproject-bwdb....**.

In the results window the first result is to extract rows from the table.

The second result is detailed of the query plan. The 3rd row in the **StmtText** column should now show "...Index Seek?. This means the index is now being correctly used.