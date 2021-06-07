# Debugging non-BUF latches

You need two command or powershell sessions for this:

1. Run setup.sql to install the database
2. Load up dmvs.sql in order to observe any latch waits
3. Run repro.cmd
4. Look for LATCH_XX waits in the DMVs
5. Run debugsql.cmd to attach the debugger
6. Run `dd "resource address>`
7. Show the breakdown of the class and look at the bytes

The first 64bits is the waiter list
The second 64bits is the owner�s task address
The next 64bits is the m_count. Break this down into bits and show the EX bit and waiters bit set. This should be 0xa The next 64bits is the class. 0x30 is 48 decimal

Copy the task address from the debugger window (byte swap it) and find the task address in the DMV output still in SSMS. Which one is it. The one waiting on PREEMPTIVE_OS_WRITEFILEGATHER.

8. What is this scenario? Review back the setup.sql script and how the files were configured.
9. Use the find_a_latch.sql script to figure out which latch class is 48