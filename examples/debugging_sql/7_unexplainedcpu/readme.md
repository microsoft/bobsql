# Unexplained SQL Server CPU

Scripts for investigating CPU associated with access checks and query
profiling. Use the isolated Windows lab described in the
[debugging collection](../readme.md).

Review [fhasaccess_setup.sql](fhasaccess_setup.sql) before creating the lab
objects, then inspect [fhasaccess.sql](fhasaccess.sql),
[queryprofiling.sql](queryprofiling.sql), and [ssmsquery.sql](ssmsquery.sql)
to choose the reproduction and observation queries. Run workload and diagnostic
queries in separate sessions and compare CPU with request/profiling evidence.

These are investigation scripts, not a production CPU fix. Confirm database
targets, stop the reproduction, and remove only the lab objects you created.
