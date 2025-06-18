# Demo for Log I/O

## Show log flushes

1. Use this XEvent script to start an XEvent session **trace_log_io.sql**:

1. Create a new database with delayed durability using the script **1_annaisasqlnewbie.sql**.

2. Show which sessions are Log Writers using the script **2_log_writer_sessions.sql**:

 run various scenarios to look at log flushing:

1. In a database where delayed durability is NOT ON using the script **3_not_delayedtransaction.sql**

Now look at the event live data. Note: if you see a flush use the SQLCallStackResolver to see what it is. You will notice this is related to QDS.

Notice the 2 background sessions:

log_flush_requested is for QDS
log_flush_start is for Log Writer
databases_log_flush_wait is for the database log flush wait

Now do a COMMIT TRAN and look at the event live data. You will see a flush related to the commit. Notice the session is is from the Log Writers

1. Change the database to delayed durability FORCED using the script **4_altertodelayed.sql**.

1. Run the same queries in **3_not_delayedtransaction.sql** again.

1. Now see how log gets flushed when not committing but filling up the log buffer. Use the script **5_fill_log_buffer.sql**

We will have delayed durability so there is no wait for flush.3_backupdbandlog

1. Show the same for a transaction with tempdb using the script **6_tempdb_transaction.sql**.

Note here there is no flush activity at all.

## BONUS: inline log writing

Show inline log writing. Enable lock pages and now see if log flushes happen inline. They only happen when the log buffer is full.