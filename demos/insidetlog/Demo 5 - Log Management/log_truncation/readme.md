# Demo for log truncation

1. Create a database like the following:

USE MASTER;
GO
DROP DATABASE IF EXISTS letsgostars;
GO
CREATE DATABASE letsgostars;
GO

3. Look at VLFs and log_reuse column

USE letsgostars;
GO
SELECT * FROM sys.dm_db_log_info(NULL);
GO
SELECT name, log_reuse_wait_desc
FROM sys.databases
WHERE name = 'letsgostars';
GO

2. Create a table for to used to hold a transaction

USE letsgostars;
GO
DROP TABLE IF EXISTS holduplogtrunc;
GO
CREATE TABLE holduplogtrunc (col1 INT);
GO

3. Backup the database

BACKUP DATABASE letsgostars TO DISK = 'c:\temp\letsgostars.bak' WITH INIT;
GO

3. Open a transaction on this table

USE letsgostars;
GO
BEGIN TRAN
INSERT INTO holduplogtrunc VALUES (1);
GO

4. Fill up the rest of the log

USE letsgostars;
GO
DROP TABLE IF EXISTS fillthelog;
GO
CREATE TABLE fillthelog (col1 INT, col2 CHAR(7000) NOT NULL);
GO
DECLARE @x INT;
SET @x = 0;
WHILE (@x < 100000)
BEGIN
    INSERT INTO fillthelog VALUES (@x, '1');
    SET @x = @x + 1;
END;
GO

5. Check the log status

USE letsgostars;
GO
SELECT * FROM sys.dm_db_log_info(NULL);
GO
SELECT name, log_reuse_wait_desc
FROM sys.databases
WHERE name = 'letsgostars';
GO

Says LOG_BACKUP is holding up truncation

6. Backup the log

BACKUP LOG letsgostars TO DISK = 'c:\temp\letsgostars_log.bak' WITH INIT;
GO

7. Check the log again

USE letsgostars;
GO
SELECT * FROM sys.dm_db_log_info(NULL);
GO
SELECT name, log_reuse_wait_desc
FROM sys.databases
WHERE name = 'letsgostars';
GO

Now says active transaction

6. Check for active transactions

USE letsgostars;
GO
-- The old way
DBCC OPENTRAN();
GO
-- A new way
SELECT
  GETDATE() as now,
  DATEDIFF(SECOND, transaction_begin_time, GETDATE()) as tran_elapsed_time_seconds,
  st.session_id,
  txt.text, 
  *
FROM
  sys.dm_tran_active_transactions at
  INNER JOIN sys.dm_tran_session_transactions st ON st.transaction_id = at.transaction_id
  LEFT OUTER JOIN sys.dm_exec_sessions sess ON st.session_id = sess.session_id
  LEFT OUTER JOIN sys.dm_exec_connections conn ON conn.session_id = sess.session_id
    OUTER APPLY sys.dm_exec_sql_text(conn.most_recent_sql_handle)  AS txt
ORDER BY
  tran_elapsed_time_seconds DESC;

Get the LSN from the OPENTRAN output and go back and see which VLF in the checklog output.

Save this LSN

7. COMMIT the transction

Uncomment this
-- COMMIT TRAN

8. Check the log again

USE letsgostars;
GO
SELECT * FROM sys.dm_db_log_info(NULL);
GO
SELECT name, log_reuse_wait_desc
FROM sys.databases
WHERE name = 'letsgostars';
GO

Why does it say ACTIVE_TRANSACTION

9. What about a CHECKPOINT?

Need a backup since we committed the tran

10. Backup the log again

BACKUP LOG letsgostars TO DISK = 'c:\temp\letsgostars_log2.bak' WITH INIT;
GO

11. Check log again

Log truncated and all good

12. Can we see truncated log records?

Using the saved LSN from the active transaction, run this query

SELECT * FROM sys.fn_dblog(NULL, NULL);
GO
DBCC TRACEON(2537);
GO
SELECT * FROM sys.fn_dblog('39:730:1', NULL);
GO


