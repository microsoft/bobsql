# Studying SOS_SCHEDULE_YIELD waits and yielding

1. Load up dm_exec_requests.sql
2. Start a XE session that traces wait_completed for SOS_SCHEDULE_YIELD waits. Watch live data
3. Run crankitup.cmd to run a workload with ostress
4. Look at results of dm_exec_requests.sql
5. Look at Task Manager showing 100% almost across the board
6. Break into the debugger and run ~*k and find thread stacks that show yields. Look for YieldAndCheckForAbort. Show threads that are running and are not waiting
7. Hit 'g' in the debugger
8. Load up rgcpucap.sql and execute it
9. Show in Task Manager how dynamically we are lowering CPU across the board
10. Run rgundocpucap.sql to put cap back to 100%