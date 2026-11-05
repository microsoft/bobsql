# Debugging waits

Follow the original [readme.txt](readme.txt) for the multi-session blocking
walkthrough. It uses [cowboys.sql](cowboys.sql), [delete_jerry.sql](delete_jerry.sql),
and [insert_jason.sql](insert_jason.sql), then inspects waiting threads with
WinDbg and [waitingtasks.sql](waitingtasks.sql).

Use an isolated Windows SQL Server instance, SSMS/sqlcmd, WinDbg, and public
symbols. Inspect [debugsql.cmd](debugsql.cmd) before attaching: debugger breaks
pause the server process. Compare the blocking worker with background threads
instead of treating every waiting thread as a problem.

For CPU/scheduler behavior, continue with
[scheduleryield](scheduleryield/readme.md). End lab transactions and detach the
debugger safely after collecting evidence.
