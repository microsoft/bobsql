# Show how to use sys.fn_db_dump_log()

1. Create and backup a database using the script **createdb.sql**.

2. Create a table using the script **2_createtable.sql**

3. Insert some data into the table using the script **3_insertdata.sql**. Only run the BEGIN TRAN and first 2 transactions. Don't execute the DELETE or COMMIT yet.

3. Run the query in the script **4_findtransaction.sql** to find the transaction. You should see the transaction in the result set.

3. Backup the log using the script **5_backuplog1.sql**.

4. In the window for the script **3_mytransaction.sql**, execute statements to delete and commit the transaction.

5. Backup the log again using the script **backuplog2.sql**.

6. Try to find the transaction using the script **3_findtrans.sql** again. You should see that the transaction is no longer there because the log has been truncated.

You see the transaction is gone because the log is truncated. How can I figure out how the table became empty?

7. Now try to find the transaction using the script **7_findmytransactionfromlogbackup.sql**. 

The first batch finds the inserts but not the delete and commit. The second batch finds the delete including a date/time