# Demo to create a stalled scheduler

1. Run setuphang.cmd to setup the repro
2. Load doupdate.sql in SSMS and run it
3. Run repro.cmd
4. Now try to run the COMMIT TRAN in the doupdate.sql.
5. Now try a new query with SSMS and it hangs
6. Run dac.cmd to use DAC from sqlcmd
7. Run this query 

dbcc traceon(8022,-1);
go

Notice the new ERRORLOG entries

Run this command

select wait_type, count(*) from sys.dm_os_waiting_tasks group by wait_type;
go

8. How do we get out of this?

We could try to kill the spid that started the tran but instead try to commit the tran in SSMS

Notice the ostress output shows SQL Server recognized the commit tran and the open requests are a "deadlock" so killed some of the incoming sessions so the commit could proceed. The system_health session should pick this up as well since it is a deadlock error.

9. But if we didn't clean this up eventually this becomes a deadlock scheduler dump scenario

Show errorlog.scheduler_deadlock file
Bring up the dump with debughangdump.cmd and show the current thread is scheduler monitor.
There a bunch of blocked threads but no other working doing anything. Why?
