# Debug the fundamentals of waits

## What does blocking look like in the debugger?

*Note:*

Here is the debugger command to use for public symbols:

`windbg -y srv*c:\public_symbols*http://msdl.microsoft.com/download/symbols -pn sqlservr.exe`

1. Show cowboys.sql. Run it.
2. Open delete_jerry. Run it
3. Open insert_jason.sql. Run it. It blocks
4. Run debugsql.cmd to attach the debugger
5. Break into the debugger and find the blocking thread by searching for LockOwner::Sleep. Show the call stack sequence
6. Show Resource Monitor thread which is waiting but notice no SQLOS routines "in between". That is because it is PREEMPTIVE
7. What should the thread look like that ran the DELETE?

## How to use DMVS and XEvents to look at waits

1. Load up exec_requests.sql and show the DMV queries
2. Load up waiting_tasks.sql and show the DMV results
4. Load up delete_jerry.sql and run the query
5. Load up insert_jason.sql and run the quer
6. Look at the results of waiting_tasks.sql. Notice the behavior for LAZYWRITER_SLEEP and the other *QUEUE* waits
6. Now look at the results from exec_requests and show the blocker and its values. Look at the results using the worker start times.
7. Bring up the system_health session in SSMS for Extended Events and look at the Target Data for the file target for this session. show the "top waits" values that exist. Remember by default we collect this every 5 minutes and even write this to a file.
8. Show XEvent session to debug any wait type (use xe_trace_events.sql to create).
9. Show Query Store Waits Reports in SSMS
10. Show SQLInsights in Azure Portal Wait Categories and Types
