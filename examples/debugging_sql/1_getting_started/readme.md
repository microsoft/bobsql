# Show fundamentals of debugging

1. Start the SQL Server Service.
2. Run debugsql.cmd to attach windbg to SQL Server with a symboth path
3. Run a few debugger commands
4. Dump out the current thrad

k

shows the current thread which is the debugger injecting a thread to do the attach

5. Dump out the callstacks for all threads

~*k

show the call stacks of all threads. Notice a bunch of threads that have the same call stack like this

  77  Id: d6c.410 Suspend: 1 Teb: 00000035`c575e000 Unfrozen
 # Child-SP          RetAddr               Call Site
00 00000035`ced7f4e8 00007ff9`23c7df19     ntdll!NtSignalAndWaitForSingleObject+0x14
01 00000035`ced7f4f0 00007ff8`faf7cc57     KERNELBASE!SignalObjectAndWait+0xd9
02 00000035`ced7f5a0 00007ff8`faf7cb70     sqldk!ThreadScheduler::SwitchWorker+0x125
03 00000035`ced7f5f0 00007ff8`faf71da7     sqldk!SOS_Scheduler::Switch+0x6b
04 00000035`ced7f660 00007ff8`faf72857     sqldk!SOS_Scheduler::SuspendNonPreemptive+0x101
05 00000035`ced7f6f0 00007ff8`faf7815c     sqldk!WaitableBase::Wait+0x10f
06 00000035`ced7f750 00007ff8`faf77d9e     sqldk!WorkDispatcher::DequeueTask+0xaf2
07 00000035`ced7f8d0 00007ff8`fafa9b23     sqldk!SOS_Scheduler::ProcessTasks+0x27e
08 00000035`ced7fa20 00007ff8`fafa9bbc     sqldk!Worker::EntryPoint+0x2f9
09 00000035`ced7fb00 00007ff8`fafa97af     sqldk!ThreadScheduler::RunWorker+0xc
0a 00000035`ced7fb30 00007ff8`fafa9ea5     sqldk!SystemThreadDispatcher::ProcessWorker+0x589
0b 00000035`ced7fc10 00007ff9`25464ed0     sqldk!SchedulerManager::ThreadEntryPoint+0x3cf
0c 00000035`ced7fd20 00007ff9`263de40b     KERNEL32!BaseThreadInitThunk+0x10
0d 00000035`ced7fd50 00000000`00000000     ntdll!RtlUserThreadStart+0x2b

This is an idle worker thread

6. Dump out the modules loaded and their symbols

lm

show modules and see the symbols loaded for each. Show the main exe and DLLs for SQL Server

7. Dump out only the unique call stacks

!uniqstack

8. Show a thread that is not a SQL worker thread

Search for this function: clr!CLREventWaitHelper2

This is an example of a thread that is not a SQL worker thread. We have to load clr.dll to be able to support SQLCLR even if it is not enabled

9. Start up SSMS to see more info

Load threads.sql to see a list of threads. Notice the column started_by_sqlservr is 0 or 1 for some

10. Let's see if we can find a background worker using DMVs

Type in 'g' to let SQL Server run

In SSMS load up find_lw_thread.sql
Break into the debugger
Take the os_thread_id value from the query and run this in the debugger
? 0n<os_thread_id>
The result is a hex number which is the thread_id
Now run this in the debugger

~~[os_thread_id in hex]k

This should be the callstack of the LazyWriter thread

11. We have two ways to leave the debugger

q - Quit and kill the process
.detach - Quit but don't kill the process