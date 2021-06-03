# Demistify THREADPOOL waits

1. Run ddl.sql to setup the database
2. Run the query in max_worker_threads.sql to set max worker threads to 255
3. Run delete.sql
4. Run query.sql. Does it wait?
5. Run waitingrequests.sql to see what waits look like.
6. Run querystress.cmd to block a bunch of workers
7. Try to connect with a new query window. Denied!
8. Now try to connect with DAC (admin:.). You can connect
9. Run waiting_requests.sql again. What is different?
10. Run waiting_tasks.sql to see THREADPOOL waits. Notice there is no worker address for these. Why?
11. Reset max worker threads to 0 in max_worker_threads.sql