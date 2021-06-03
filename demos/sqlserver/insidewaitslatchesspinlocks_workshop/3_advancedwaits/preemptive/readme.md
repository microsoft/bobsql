# Observing the details of a PREEMPTIVE wait scenario

1. Run setup.sql to setup the repro
2. Load dmvs.sql into SSMS
3. Run .\repro.cmd
4. Run dmvs queries
5. Point out that lead blocker in SQL 2005 would have been a wait_type of NULL
6. Point out latch stats information
7. Attach the debugger (use debugsql.cmd) and look at the call stacks
