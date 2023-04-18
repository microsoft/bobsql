# Demo to show how to create an index with a lower priority locking for better concurrency

This is a demo to show how we have better concurrency for create index operations with SQL Server 2022.

## Setup

1. Execute the script **customer_ddl.sql**

## See how a query get blocked with an offline index

1. Execute the script **long_running_query.sql**
1. Execute the script **create_index_offline.sql** to create an index.
1. Execute the script **query_gets_blocked.sql**.
1. Execute the script **get_blockers.sql** to see how the query is blocked by the index creation.
1. Execute the script **findlocks.sql** to see what locks are held.

## See how a query get blocked with an online index

1. Execute the script **long_running_query.sql**
1. Execute the script **create_index_online.sql** to create an index.
1. Execute the script **query_gets_blocked.sql**.
1. Execute the script **get_blockers.sql** to see how the query is blocked by the index creation.
1. Execute the script **findlocks.sql** to see what locks are held.

## See how a query get blocked with an online index with a low priority wait

1. Execute the script **long_running_query.sql**
1. Execute the script **create_index_online_low_priority.sql** to create an index.
1. Execute the script **query_gets_blocked.sql**. Notice the query is not blocked.