# Debugging non-BUF latches

1. Start SQL Server Service
2. Run prep.sql
2. Run xe.sql to start an XEvent session
3. Load up dmvs.sql to monitor blocking
4. Run setup.sql to create a new database
5. Run repro.cmd
6. What does the output of the dmvs.sql look like?
7. When blocking is done what does XEvent look like?
8. Copy call stacks and look at SQLCallStackResolver and explain code and stacks
9. Bring up WriteFileGather in internet search
10. Why does it take so long to do this. Show the T-SQL code in setup.sql and start.sql
11. Restart the SQL Server Service to make sure and clear any trace flags

