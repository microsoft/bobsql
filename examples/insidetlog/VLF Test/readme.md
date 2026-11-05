# VLF growth experiments

Additional experiments for virtual log files, log growth, and open
transactions. These complement [Demo 1](<../Demo 1 - Transaction Log File/readme.md>).

1. Read [vlftestnotes.sql](vlftestnotes.sql) to establish the intended sequence.
2. Inspect [bigtab.sql](bigtab.sql), [growfile.sql](growfile.sql), and
   [opentran.sql](opentran.sql) for database names, file sizes, and transaction
   boundaries before selecting an experiment.
3. Use a disposable SQL Server database and record VLF/log-space observations
   before and after the chosen operation.

Growth and open transactions can consume substantial disk space and prevent
log reuse. Close or roll back lab transactions and restore the intended lab
configuration afterward. Do not copy file-growth settings into production.
