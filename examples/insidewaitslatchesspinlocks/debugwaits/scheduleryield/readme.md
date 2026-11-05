# Scheduler-yield and CPU lab

Use the original [readme.txt](readme.txt) for the intended workload sequence.
The folder includes CPU workloads, a driver command, request diagnostics, and
Resource Governor CPU-cap examples.

Inspect [cpuquery.sql](cpuquery.sql), [crankitup.cmd](crankitup.cmd), and
[dm_exec_requests.sql](dm_exec_requests.sql) before running against a disposable
SQL Server lab. Compare runnable work and scheduler waits with CPU use rather
than assuming a wait count alone proves a bottleneck.

Resource Governor scripts change instance configuration. Review
[rgcpucap.sql](rgcpucap.sql) and [rgundocpucap.sql](rgundocpucap.sql), obtain
approval for changes, stop the workload, and restore the original settings.
