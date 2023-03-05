# Demos for an Access Violation

1. Load up **crash.sln** in Visual Studio

- Show the basics of the code
- Hit Play
- Show the console window with exit code. The number in hex is **C0000005**. Show **winnt.h** for what C0000005 means which is STATUS_ACCESS_VIOLATION
- Now uncomment the code for SEH and show the behavior. That is what SQL Server tries to do for many AVs.

2. Show an AV with SQL Server

- Stop the SQL Server Service
- Run the debug server from the debugsql\debug\sqlservr directory using **sqlservr.cmd**
- Load **crash.sql** and talk about **DBCC UNITTEST**
- Show the ERRORLOG
- Call stack is in the ERRORLOG but let's use the debugger
- Go to the c:\debugsql\debug\sqlservr\log directory. Talk about the SQLDUMPER_ERRORLOG.LOG file
- Edit **debugav.cmd** to put in the name of the MDMP file and run it.
- Show the header at the top of the debugger
- To get the right AV context type in `.ecxr`
- Type in `k` to see the callstack
- Show the assembly instruction for the AV. Type `r` to see registers and show it is a write to **rax** which is 0.

3. Now let's have some fun and cause our own AV

- Stop the debug server
- Startup the normal SQL Server service
- Attach the debugger with **debugsql.cmd**
- Set a breakpoint with this command

    `bp sqllang!process_commands`
    `g`

4. Try to run a query with SSMS

- Trace the assembly until you get to this line of code

    ```mov     rax,qword ptr [rcx] ds:000001b3`11138f40={sqllang!CBatch::`vftable' (00007ffb`68058478)}```

Now type in

    `bd 0`
    `r rcx=0`
    `gu`
    `g`

- Go look at the ERRORLOG directory and see the AV. Notice there is no input buffer because we hit an AV before the server read in the query

5. Detach the debugger and shutdown SQL Server
