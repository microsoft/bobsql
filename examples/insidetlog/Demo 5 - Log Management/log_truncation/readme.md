# Demo for log truncation

1. Create a database from the script **1_createdb.sql**.

3. Look at VLFs and log_reuse column from **2_checkthelog.sql**.

2. Create a table for to used to hold a transaction with the script **3_createtable.sql**

3. Backup the database using the script **4_backupdb.sql**.

3. Open a transaction on this table using the script **5_newtransaction.sql**.

4. Check log status with **2_checkthelog.sql**. Why doesn't it say ACTIVE_TRANSACTION? First kickoff next script as it takes some time.

4. Fill up the rest of the log using the script **6_fillthelog.sql**.

5. Check the log status again with **checkthelog.sql**. Why does it say LOG_BACKUP?

It says LOG_BACKUP is holding up truncation

6. Backup the log with the script **backuplog.sql**

7 . Check the log status again with **checkthelog.sql**. Why does it say ACTIVE_TRANSACTION?

6. Check for active transactions using the script **8_checkactivetransactions.sql**

Get the LSN from the OPENTRAN output and go back and see which VLF in the checklog output.

Save this LSN

7. COMMIT the transction from **5_newtransaction.sql**.

8. Check the log again from **2_checkthelog.sql**. Why does it say ACTIVE_TRANSACTION?

Why does it say ACTIVE_TRANSACTION? Because even though the transaction is committed this is the last "known" reason we cannot truncate the log.

9. How about a CHECKPOINT? Run the script **9_checkpoint.sql**.

10. Now check the log status again with **2_checkthelog.sql**. Why does it say LOG_BACKUP?

10. Backup the log again using the script from **10_backuplog2.sql**

1. Check the log status again with **2_checkthelog.sql**. Log truncated and all good

12. Can we see truncated log records? Load the script **11_findoldlsn.sql** and paste in your active LSN.
