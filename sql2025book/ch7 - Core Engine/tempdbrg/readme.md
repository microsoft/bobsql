# Tempdb space resource governance

This is a demo for the tempdb resource governor feature in SQL Server 2025. This feature is designed to help you manage the space used by tempdb by configuring the Resource Governor to limit the space used by tempdb for users both for explicit temporary tables or internal space used for operations like sorts.

## Prerequisites

1. Use the prerequisites in the [SQL Server 2025 Engine Demos](../../readme.md) readme.

2. You will need to enable mixed mode authentication for the SQL Server instance you are using. This is because the demo will use a new SQL login to demonstrate the tempdb space resource governance feature. You can do this by following the instructions in the [Enable mixed mode authentication](https://learn.microsoft.com/sql/database-engine/configure-windows/mixed-mode-authentication?view=sql-server-ver15) documentation.

## References

Find out more about tempdb space resource governance at https://learn.microsoft.com/sql/relational-databases/resource-governor/tempdb-space-resource-governance

## Scenario

Consider a scenario where you as an administrator struggle to manage the growth of the size of tempdb due to users that may not be aware of the impact of their queries on tempdb. This can lead to performance issues and contention in tempdb.
To address this, you can use the tempdb space resource governance feature to limit the space used by tempdb for users both for explicit temporary tables or internal space used for operations like sorts.

## Setup

Follow these steps connected as a sysadmin login.

1. Set the tempdb size

In this scenario you want to establish the default size of tempdb to be 512MB across 8 tempdb data files and a 100MB tempdb log file. You can do this by executing the script **settempdbsize.sql** in a SSMS query editor window. This will set the size of tempdb to 512MB across 8 data files and a 100MB log file.

You decide to leave autogrow for tempdb files to avoid any downtime situations but your goal is to make sure growth does not exceed 512MB because you have carefully planned the usage of tempdb through temporary tables from your developers.

Execut the script **checktempdbsize.sql** in a SSMS query editor window to verify the size of tempdb. You should see that the size of tempdb is 512MB across 8 data files and a 100MB log file.

2. Create a user database to show unexpected tempdb growth

Load and execute the script **createbigdata.sql** in a SSMS query editor window.

3. Create a new SQL login and grant it access to the user database and table

Load and execute the script **createuser.sql** in a SSMS query editor window. 

4. Create a database to represent experienced SQL users

Load and execute the script **iknowsql.sql** in a SSMS query editor window. This will create a database called iknowsqldb. This includes a table and stored procedure that will create a temporary table of fixed size which ensures a more controlled use of tempdb.

## Show controlled tempdb usage

1. Load and execute the script **processdata.sql** in a SSMS query editor window. This script will execute the stored procedure in the iknowsqldb database to process data and create a temporary table of fixed size.

2. Load and execute the script **checktempdbsize.sql** in a SSMS query editor window. This script will check the size of tempdb. Notice there is no growth of tempdb and space used is small. Even if the procedure were run by many concurrency users, overall tempdb space would not grow beyond the 512MB limit set.

3. Load and execute the script **tempdb_session_usage.sql** in a SSMS query editor window. This shows the small amount of tempdb space used by the session that executed the stored procedure for an explicit temporary table. 

## Show uncontrolled tempdb usage

1. Connect to SSMS using the SQL login created in the **createuser.sql** script. This will be the user that does not know how to control tempdb usage. You must set the Application Name in the connection properties to "GuyInACube" so you can see the application as unique and not from SSMS.

2. Run a query that causes tempdb to grow using the same user.

Load the and execute the script **guyinacubepoorquery.sql** in a SSMS query editor window. This script will take a few minutes to run. It wil run a query that requires a large sort which requires tempdb space. Use the show actual execution plan to see a sort has ocurred. This query will cause tempdb to grow significantly as it requires a large sort operation that exceeds the 512MB limit set for tempdb.

3. Connect to SSMS using the sysadmin login from before to check the size of tempdb.

Load and execute the script **checktempdbsize.sql** in a SSMS query editor window. This script will check the size of tempdb. Notice that the size of tempdb has grown significantly due to the poor query executed by the user.

4. Using the same sysadmin login, check to see who has consumed the space.

Load and execute the script **tempdb_session_usage.sql** in a SSMS query editor window. This script will show you the sessions that have consumed space in tempdb. You can see the session that caused the abnormal growth of tempdb is the one with the Application Name "GuyInACube".

## Setup Resource Governor to control tempdb space usage

Connect to SSMS using the sysadmin login from before. You will now set up the Resource Governor to control the space used by tempdb.

1. To show this scenario, set the tempdb size back to the original size of 512MB across 8 data files and a 100MB log file. You can do this by executing the script **settempdbsize.sql** in a SSMS query editor window. Restart SQL Server.

2. Setup resource governor to limit the space used by tempdb for users both for explicit temporary tables or internal space used for operations like sorts.

Load and execute the script **setuprg.sql** in a SSMS query editor window. This script will set up the Resource Governor to limit the space used by tempdb for users both for explicit temporary tables or internal space used for operations like sorts but for a specific workload group.

3. Create a new classifier function for the resource workload group

Load and execute the script **classifierfunction.sql** in a SSMS query editor window. This script will create a classifier function that will classify the sessions based on the Application Name. In this case, it will classify the sessions with the Application Name "GuyInACube" to the workload group that has the tempdb space limit set.

## Test our tempdb is now limited for the workload group

1. Connect to SSMS again as the SQL login created in the **createuser.sql** script. This will be the user that does not know how to control tempdb usage. You must set the Application Name in the connection properties to "GuyInACube" so you can see the application as unique and not from SSMS.

2. Run the same query that caused tempdb to grow using the same user

Load and execute the script **guyinacubepoorquery.sql** in a SSMS query editor window. After a few seconds you will see this query fails with the following error:

```
Msg 1138, Level 17, State 1, Line 3
Could not allocate a new page for database 'tempdb' because that would exceed the limit set for workload group 'GroupforUsersWhoDontKnowSQL'.
```
3. Connect to SSMS using the sysadmin login from before to check the size of tempdb and resource governor details.

Load and execute the script **checktempdbsize.sql** in a SSMS query editor window. This script will check the size of tempdb. Notice that the size of tempdb has not grown beyond the 512MB limit set as before.

Load and execute the script **checktempdbrg.sql** in a SSMS query editor window. This script will show workload groups, their peak tempdb usage, and any violations of the tempdb space limit. You can see that the workload group for the user "GuyInACube" has violated the tempdb space limit set.

## Resetting any resources

To run through this demo again execut the following steps:

1. Disable the Resource Governor for tempdb by executing the script **disablerg.sql** in a SSMS query editor window as a sysadmin login.

2. Reset the tempdb size by executing the script **settempdbsize.sql** in a SSMS query editor window as a sysadmin login. Restart SQL Server.
