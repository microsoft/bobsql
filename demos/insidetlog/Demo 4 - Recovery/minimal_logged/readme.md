# Demo for minimially logged transactions

1. Create the minimally logged database using the script **1_create_bulklogdb.sql**

2. Create a table and populate some rows using the s ript **2_createtab.sql**.

3. Backup the db and log so I can truncate it to see the log records easier using the script **3_backupdbandlog.sql**.

2. Run a SELECT INTO using **4_selectinto.sql**

3. Examine log records using the script **5_examinelogrecords.sql**. Notice the log records and the log record length. For minimally logged we just log changes to allocation pages.

1. Now do the same for a full recovery db in **6_fullrecdb.sql**. Notice here the "fully logged" is formatting full pages instead of logging INSERTs.