# Demo for SQL Server Ledger for SQL Server 2022

These are demonstrations for SQL Server Ledger for SQL Server 2022

## Prerequisistes

- SQL Server 2022 Evaluation Edition. You must configure SQL Server for mixed mode authentication.
- Virtual machine or computer with minimum 2 CPUs with 8Gb RAM.
- SQL Server Management Studio (SSMS). The latest SSMS 18.x will work but SSMS 19.x has a new visualization for Ledger tables so the examples in demo 1 were done with the latest SSMS 19.x preview build.

## Demo 1: Using an updatable ledger table

This demo will show you the fundamentals of an updatable ledger table.

1. Create logins by executing the script **addsysadminlogin.sql** from SSMS as the default sysadmin for the SQL Server instance.
2. Login with the 'bob' sysadmin user created in step #1.
2. Create the database schema, add an app login, and users by executing the script **createdb.sql** from SSMS.
3. Create an updateable ledger table for Employees by executing the script **createemployeeledger.sql** from SSMS.
4. Create an append-only ledger table for auditing of the application by executing the script **createauditledger.sql** from SSMS. This table will be used later in the demonstration.
5. Populate initial employee data using the script **populateemployees.sql** from SSMS. Use SSMS Object Explorer to see the tables have properties next to their name that they are ledger tables and a new visual icon to indicate it is a ledger table.
6. Examine the data in the employee table using the script **getallemployees.sql**. Notice there are "hidden" columns that are not shown if you execute a SELECT *. Some of these columns are NULL or 0 because no updates have been made to the data. You normally will not use these columns but use the *ledger view* to see information about changes to the employees table.
7. Look at the employees "ledger" by executing the script **getemployeesledger.sql**. This is a view from the Employees table and a ledger *history* table. Notice the ledger has the transaction information from hidden columns in the table plus an indication of what type of operation was performed on the ledger for a specific row.
8. Examine the definition of the ledger view by executing **getemployeesledgerview.sql**. The ledger history table uses the name**MSSQL_LedgerHistoryFor_[objectid of table]**. Notice the view is a union of the original table (for new inserts) and updates from the history table (insert/delete pair).
9. You can combine the ledger view with a system table to get more auditing information. Execute the script  **viewemployeesledgerhistory.sql** to see an example. You can see that 'bob' inserted all the data along with a timestamp.
10. To verify the integrity of the ledger let's generate a digest by executing the script **generatedigest.sql**. **Save the output value (including the brackets) to be used for verifying the ledger.**
11. You can now see blocks generated for the ledger table by executing the script **getledgerblocks.sql**
10. Try to update Jay Adam's salary to see if no one will notice by executing the script **updatejayssalary.sql**.
11. Execute the script **getallemployees.sql** to see that it doesn't look anyone updated the data. But notice in the 2nd query result, the **ledger_start_transaction_id** is different than from the 1st insert.
12. Execute the script **viewemployeesledgerhistory.sql** to see the audit of the changes and who made them.
13. Let's verify the ledger just to verify the integrity of the data. Edit the script **verifyledger.sql** by substituting the JSON value from **step 10** from the **generatedigest.sql** script (include the brackets inside the quotes). Execute the script. The **last_verified_block_id** should match the block_id in the digest and in **sys.database_ledger_blocks**. I now know the ledger is verified as of the time the digest was captured. By using this digest I know that 1) The data is valid based on the time the digest was captured 2) The internal blocks match the current data changes for the update to jay's salary. If someone had to fake out the data for the Employees table without doing a T-SQL UPDATE to make the system "think" Jay's current salary was 50,000 more than it really is, the system would have raised an error that hashes of the changes don't match the current data.

## Demo 2: Using an append-only ledger

Now see you can use an append-only ledger to capture application information. To ensure we captured what person was responsible for changes even if an application uses an "application login" we can use an append-only ledger table which was created earlier then you ran the script **createauditledger.sql**.

1. To simulate a user using the application to change someone else's salary **connect to SSMS as the app login** created with the **addlogins.sql** script in step 1 and execute the script **appchangemaryssalary.sql**
1. **Logging back in as bob or the local sysadmin login**, look at the ledger by executing the script **viewemployeesledgerhistory.sql**. All you can see is that the "app" changed Mary's salary.
1. Look at the audit ledger by executing the script **getauditledger.sql**. This ledger cannot be updated so the app must "log" all operations and the originating user from the app who initiated the operation. So I can see from the ledger at the SQL level that the app user changed Mary's salary but the app ledger shows bob was the actual person who used the app to make the change.

## Demo 3: Protecting Ledger tables from DDL changes.

Let's see how admin trying to change ledger table properties or drop ledger tables

1. You can also view which tables and columns have been created for SQL Server ledger by executing the script **getledgerobjects.sql**
1. Admins are restricted from altering certain aspects of a ledger table, removing the ledger history table, and there is a record kept of any dropped ledger table (which you cannot drop). See these aspects of ledger by executing the script **admindropledger.sql**
1. Execute **getledgerobjects.sql** again to see the dropped ledger table.