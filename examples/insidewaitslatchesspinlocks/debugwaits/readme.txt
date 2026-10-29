Demo instructions:

1. Show cowboys.sql. Run it.
2. Open delete_jerry. Run it
3. Open insert_jason.sql. Run it. It blocks
4. Run debugsql.cmd to attach the debugger
5. Break into the debugger and find the blocking thread by searching for LockOwner::Sleep.
Show the call stack sequence
6. Show Resource Monitor thread which is waiting but notice no SQLOS routines "in between". That is because it is PREEMPTIVE
7. What should the thread look like that ran the DELETE?
8. Load up waitingtasks.sql and note the behavior of LAZY WRITER (timer) and CHECKPOINT (signaled)

Note:

Here is the debugger command to use for public symbols:

windbg -y srv*c:\public_symbols*http://msdl.microsoft.com/download/symbols -pn sqlservr.exe
