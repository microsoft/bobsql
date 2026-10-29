# Demo to show the new query_abort event

1. Start a SQL Server 2022 service
2. Use xevent_session.sql to start an XEvent session and Watch Live Data
3. Load user_cancel.sql and run it in SSMS. Cancel it after a few seconds.
4. In the XEvent session copy the call sack and use SQLCallstackResolver to get the call stack. Notice that the call stack is in the "middle" of executing somthing. Explain how an ATTENTION works.
5. Load ddl.sql and run it.
6. Use sqlcmd from the command prompt (not powershell) to run:

sqlcmd -E -Q"select * from tab with (holdlock);" -dmaster -t2

7. Look at the call stack and see that the abort is during a wait. Use this symbol path: C:\temp\16.0.950.9.x64;https://msdl.microsoft.com/download/symbols