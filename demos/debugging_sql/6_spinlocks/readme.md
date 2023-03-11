# Debugging a spinlock

1. Restart sql server with **startsqllockhash.cmd**
- Create a database called **lockhashme**.
- Make sure SQL Server is using Mixed Mode Authentication.
- Create a login called **test** with password of **test** and make that dbo of the lockhasme db. When you create the login in SSMS uncheck the password restrictions.
2. Load up **execrequests.sql** and get_**spinlock_stats.sql** to observe waits and spinlock stats Notice a bunch of RUNNABLE requests. These are ones waiting to get scheduled.
3. Run start **connectme.cmd**. This connects a bunch of users to the same db
4. Run **resetit.cmd** to run a workload to connect/disconnect
1. Look at Task Manager CPU Utilization.
1. Observe CPU and spinlock stats. Look at Query store to see no one query chewing up a bunch of CPU.
1. Execute debugsql.cmd to attach the debugger to the running SQL Server. This could take a few mins due to high CPU.

2. Set a breakpoint on the "backoff" code like this

    `bp sqldk!SpinlockBase::Backoff`

3. Type in

    `g`

4. Dump out callstack using k when the breakpoint is hit. It should look similar to this:

```armasm
 # Child-SP          RetAddr               Call Site
00 000000b9`83df9748 00007ffc`abb70191     sqldk!SpinlockBase::Backoff
01 000000b9`83df9750 00007ffc`abb7004d     sqlmin!Spinlock<187,7,257>::SpinToAcquireWithExponentialBackoff+0x1f5
02 000000b9`83df97d0 00007ffc`ad49aa5c     sqlmin!lck_lockInternal+0x10aa
03 000000b9`83dfb440 00007ffc`abb55ffc     sqlmin!XactWorkspaceImp::GetSharedDBLockFromLockManager+0x20d
04 000000b9`83dfb550 00007ffc`abb535e4     sqlmin!XactWorkspaceImp::GetDBLockLocal+0x2ea
05 000000b9`83dfb970 00007ffc`abb546c2     sqlmin!XactWorkspaceImp::GetDBLock+0x94
06 000000b9`83dfba80 00007ffc`abb54c05     sqlmin!lockdb+0x62
07 000000b9`83dfbad0 00007ffc`abbeef56     sqlmin!DBMgr::OpenDB+0x288
08 000000b9`83dfbdc0 00007ffc`a981502c     sqlmin!sqlusedb+0x1fb
09 000000b9`83dfbec0 00007ffc`a981537c     sqllang!LoginUseDbHelper::UseByMDDatabaseId+0x9c
0a 000000b9`83dfbfb0 00007ffc`a9818858     sqllang!LoginUseDbHelper::FDetermineSessionDb+0x3a9
0b 000000b9`83dfc9a0 00007ffc`a98192af     sqllang!FRedoLoginImpl+0xce8
0c 000000b9`83dfd2b0 00007ffc`a97efcfc     sqllang!FRedoLogin+0x14f
0d 000000b9`83dfe5b0 00007ffc`a8cfee7f     sqllang!process_request+0x3af
0e 000000b9`83dfed30 00007ffc`a8cfefa0     sqllang!process_commands_internal+0x5c1
0f 000000b9`83dfee70 00007ffd`0afc875b     sqllang!process_messages+0x1e0
10 000000b9`83dff020 00007ffd`0afc8d68     sqldk!SOS_Task::Param::Execute+0x232
11 000000b9`83dff620 00007ffd`0afc88c4     sqldk!SOS_Scheduler::RunTask+0x182
12 000000b9`83dff720 00007ffd`0afe8783     sqldk!SOS_Scheduler::ProcessTasks+0x344
13 000000b9`83dff870 00007ffd`0afe865c     sqldk!Worker::EntryPoint+0x2f9
14 000000b9`83dff950 00007ffd`0afe8405     sqldk!ThreadScheduler::RunWorker+0xc
15 000000b9`83dff980 00007ffd`0afe8e05     sqldk!SystemThreadDispatcher::ProcessWorker+0x589
16 000000b9`83dffa60 00007ffd`725c26bd     sqldk!SchedulerManager::ThreadEntryPoint+0x3cf
17 000000b9`83dffb70 00007ffd`7326a9f8     KERNEL32!BaseThreadInitThunk+0x1d
18 000000b9`83dffba0 00000000`00000000     ntdll!RtlUserThreadStart+0x28
```

4. Notice this part of the call stack

    `sqlmin!Spinlock<187,7,257>::SpinToAcquireWithExponentialBackoff+0x1f5`

This is our code to "get" the spinlock AFTER we have attempted to get it once (start the spin, acquire, backoff)

Type in this to get the symbol address for `sqlmin!Spinlock<187,7,257>::SpinToAcquireWithExponentialBackoff+0x1f5`

```armasm
x sqlmin!Spinlock<187,7,257>::SpinToAcquireWithExponentialBackoff
```
you should see something like this

```armasm
00007ffc`abb6fe20 sqlmin!Spinlock<187,7,257>::SpinToAcquireWithExponentialBackoff (private: void __cdecl Spinlock<187,7,257>::SpinToAcquireWithExponentialBackoff(unsigned __int64))
```

Take that value and use the "uf" function to dump out the assembly

```armasm
uf 00007ffc`abb6fe20
```
7. Search this for keyword **cmpxchg** (search up)

You will see something like this

```armasm
00007ffc`abb6ffcf f04d0fb126      lock cmpxchg qword ptr [r14],r12
```
This is the "compare and swap" instruction called cmpxchg on Intel CPUs. In our code we actually call **InterlockedCompareExchange()** but this is a compiler "intrinsic" so not a call into any DLL. It gets translated into this instruction

8. The <1873,7,257> is a designator for a "template" class. The interesting part here is the 187 represents the "id"
of the spinlock type or name. What does this map to?

type in

    `bd *`
    `g`

to disable breakpoints and go so we can run a query.

Run this query

```sql
select * from sys.dm_xe_map_values
where name = 'spinlock_types' and map_key = 187
```
and you will find that the name of this spinlock is **LOCK_HASH**
