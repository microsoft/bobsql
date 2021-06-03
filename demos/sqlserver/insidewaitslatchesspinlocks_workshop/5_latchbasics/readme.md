# Look at latch waits through DMVs

1. Load up findingwaiters.sql. Run the queries for wait_stats and latch_stats
2. Now load up countthecowboys.sql
3. Run the queries in countthecowboys.sql
4. Run the query in findingwaiters.sql for exec_stats. Note CXPACKET wait
5. Run the query in findingwaiters.sql for wait_stats and see the LATCH_XX wait, resource_address, and description.