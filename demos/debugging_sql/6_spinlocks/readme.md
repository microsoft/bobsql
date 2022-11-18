# Debugging a spinlock

1. restart sql server with startsqllockhash.cmd
- Create a database called lockhashme.
- Create a login called test with password of test and make that dbo of the db
2. Load up execrequests.sql and get_spinlock_stats.sql to observe waits and spinlock stats 
3. Run start connectme.cmd. This connects a bunch of users to the same db
4. Run resetit.cmd to run a workload to connect/disconnect
5. Observe CPU and spinlock stats. Look at Query store to see no one query chewing up a bunch of CPU
6. Attach windbg with public symbols like this:

`windbg -y srv*c:\symbols*http://msdl.microsoft.com/download/symbols -pn sqlservr.exe`

2. Set a breakpoint on the "backoff" code like this

`bp sqldk!SpinlockBase::Backoff`

3. Type in

`g`

4. Dump out callstack using k when the breakpoint is hit. It should look similar to this:

00 000000e3`31679608 00007ff9`04a89b21     sqldk!SpinlockBase::Backoff
01 000000e3`31679610 00007ff9`04a899dd     sqlmin!Spinlock<183,7,257>::SpinToAcquireWithExponentialBackoff+0x1f5
02 000000e3`31679690 00007ff9`0634236c     sqlmin!lck_lockInternal+0x10aa
03 000000e3`3167b300 00007ff9`04a6545c     sqlmin!XactWorkspaceImp::GetSharedDBLockFromLockManager+0x20d
04 000000e3`3167b410 00007ff9`04a64b94     sqlmin!XactWorkspaceImp::GetDBLockLocal+0x2ea
05 000000e3`3167b830 00007ff9`04a66672     sqlmin!XactWorkspaceImp::GetDBLock+0x94
06 000000e3`3167b940 00007ff9`04a66bb5     sqlmin!lockdb+0x62
07 000000e3`3167b990 00007ff9`04a8b026     sqlmin!DBMgr::OpenDB+0x288
08 000000e3`3167bc80 00007ff8`fd0d981c     sqlmin!sqlusedb+0x1fb
09 000000e3`3167bd80 00007ff8`fd0d9b6c     sqllang!LoginUseDbHelper::UseByMDDatabaseId+0x9c
0a 000000e3`3167be70 00007ff8`fd0dd048     sqllang!LoginUseDbHelper::FDetermineSessionDb+0x3a9
0b 000000e3`3167c860 00007ff8`fd0dda9f     sqllang!FRedoLoginImpl+0xce8
0c 000000e3`3167d170 00007ff8`fd0b448c     sqllang!FRedoLogin+0x14f
0d 000000e3`3167e470 00007ff8`fc6681af     sqllang!process_request+0x3af
0e 000000e3`3167ebf0 00007ff8`fc667f70     sqllang!process_commands_internal+0x5c1
0f 000000e3`3167ed30 00007ff9`07b388bb     sqllang!process_messages+0x1e0
10 000000e3`3167eee0 00007ff9`07b38288     sqldk!SOS_Task::Param::Execute+0x232
11 000000e3`3167f4e0 00007ff9`07b37de4     sqldk!SOS_Scheduler::RunTask+0x182
12 000000e3`3167f5e0 00007ff9`07b69b23     sqldk!SOS_Scheduler::ProcessTasks+0x344
13 000000e3`3167f730 00007ff9`07b69bbc     sqldk!Worker::EntryPoint+0x2f9
14 000000e3`3167f810 00007ff9`07b697af     sqldk!ThreadScheduler::RunWorker+0xc
15 000000e3`3167f840 00007ff9`07b69ea5     sqldk!SystemThreadDispatcher::ProcessWorker+0x589
16 000000e3`3167f920 00007ff9`355f4ed0     sqldk!SchedulerManager::ThreadEntryPoint+0x3cf
17 000000e3`3167fa30 00007ff9`370be40b     KERNEL32!BaseThreadInitThunk+0x10
18 000000e3`3167fa60 00000000`00000000     ntdll!RtlUserThreadStart+0x2b

4. Notice this part of the call stack

sqlmin!Spinlock<183,7,257>::SpinToAcquireWithExponentialBackoff+0x1f5

This is our code to "get" the spinlock AFTER we have attempted to get it once (start the spin, acquire, backoff)

The <183,7,257> is a designator for a "template" class. The interesting part here is the 183 represents the "id"
of the spinlock type or name. What does this map to?

type in

`bd *`
`g`

to disable breakpoints and go so we can run a query.

Run this query

select * from sys.dm_xe_map_values
where name = 'spinlock_types' and map_key = 156

and you will find that the name of this spinlock is LOCK_HASH

5. Back to our code. What does the code look like to "acquire" the spinlock? The "compare and swap"?

Enable the breakpoint by typing in

`be *`
`g`

6. You should hit a breakpoint pretty quickly again that looks the same as before. Let's find the "compare and swap" code

Type in this to get the symbol address for sqlmin!Spinlock<183,7,257>::SpinToAcquireWithExponentialBackoff+0x1f5

x sqlmin!Spinlock<183,7,257>::SpinToAcquireWithExponentialBackoff

you should see something like this

00007ff9`050897b0

Take that value and use the "uf" function to dump out the assembly

`uf 00007ffd``7caae500`

7. Search this for keyword cmpxchg

You will see something like this

00007ff9`0508995f f04d0fb126      lock cmpxchg qword ptr [r14],r12

This is the "compare and swap" instruction called cmpxchg on Intel CPUs. In our code we actually call InterlockedCompareExchange() but this is a compiler "intrinsic" so not a call into any DLL. It gets translated into this intruction

8. Now scroll down and look at the instructions and branches to either call the backoff or "loop back" and do it all over again.