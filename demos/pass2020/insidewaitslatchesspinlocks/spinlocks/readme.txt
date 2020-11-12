1. restart sql server with startsqllockhash.cmd
2. Load up execrequests.sql and get_spinlock_stats.sql to observe waits and spinlock stats 
3. Run start connectme.cmd. This connects a bunch of users to the same db
4. Run resetit.cmd to run a workload to connect/disconnect
5. Observe CPU and spinlock stats. Look at Query store to see now one query chewing up a bunch of CPU
6. Attach windbg with public symbols like this:

windbg -y srv*c:\public_symbols*http://msdl.microsoft.com/download/symbols -pn sqlservr.exe

2. Set a breakpoint on the "backoff" code like this

bp sqldk!SpinlockBase::Backoff

3. Hit "g" to go

4. Dump out callstack using k when the breakpoint is hit. It should look similiar to this:

00 00000000`13c5df98 00007ffd`7caae69c sqldk!SpinlockBase::Backoff
01 00000000`13c5dfa0 00007ffd`7caae65d sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff+0x169
02 00000000`13c5e000 00007ffd`7caa249d sqlmin!LockReference::Release+0x10e
03 00000000`13c5e150 00007ffd`7ca9fbc4 sqlmin!BTreeRow::ReleaseLock+0x8c
04 00000000`13c5e180 00007ffd`7ca9f77d sqlmin!IndexDataSetSession::GoDormantInternal+0x121
05 00000000`13c5e1f0 00007ffd`7caa19de sqlmin!DatasetSession::GoDormant+0x1d
06 00000000`13c5e220 00007ffd`7caa5e09 sqlmin!RowsetNewSS::GoDormant+0x94
07 00000000`13c5e280 00007ffd`7caa8372 sqlmin!CMEDScanBase::ReleaseRowsets+0x51
08 00000000`13c5e2d0 00007ffd`7caa8c22 sqlmin!CMEDCatalogDatabase::FGetNextDatabase+0x2b3
09 00000000`13c5e3f0 00007ffd`7caa8a96 sqlmin!FsStorageCollector::CollectUnusedFiles+0x1c2
0a 00000000`13c5e4c0 00007ffd`7caa8863 sqlmin!CFsStorageCleanupTask::TimerFunction+0x4c
0b 00000000`13c5e4f0 00007ffd`7caa8053 sqlmin!CFsStorageCleanupTask::ProcessTskPkt+0x66
0c 00000000`13c5e520 00007ffd`7caa7cfa sqlmin!TaskReqPktTimer::ExecuteTask+0x63
0d 00000000`13c5e600 00007ffd`7a7e499f sqlmin!OnDemandTaskContext::ProcessTskPkt+0x3e2
0e 00000000`13c5e850 00007ffd`7caa79d5 sqllang!SystemTaskEntryPoint+0x426
0f 00000000`13c5f3d0 00007ffd`bf2d4780 sqlmin!OnDemandTaskContext::FuncEntryPoint+0x25
10 00000000`13c5f400 00007ffd`bf2d4547 sqldk!SOS_Task::Param::Execute+0x21e

4. Notice this part of the call stack

01 00000000`13c5dfa0 00007ffd`7caae65d sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff+0x169

This is our code to "get" the spinlock AFTER we have attempted to get it once (start the spin, acquire, backoff)

The <129,7,1> is a designator for a "template" class. The interesting part here is the 129 represents the "id"
of the spinlock type or name. What does this map to?

type in

bd *
g

to disable breakpoints and go so we can run a query.

Run this query

select * from sys.dm_xe_map_values
where name = 'spinlock_types' and map_key = 156

and you will find that the name of this spinlock is LOCK_HASH

5. Back to our code. What does the code look like to "acquire" the spinlock? The "compare and swap"?

Enable the breakpoint by typing in

<ctrl+break>
be *
g

6. You should hit a breakpoint pretty quickly again that looks the same as before. Let's find the "compare and swap" code

Type in this to get the symbol address for sqlmin!Spinlock<129 ,7 ,1>::SpinToAcquireWithExponentialBackoff

x sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff

you should see something like this

00007ffd`7caae500 sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff (<no parameter info>)

Take that value and use the "uf" function to dump out the assembly

uf 00007ffd`7caae500

7. Now backup and find the start of this output. Then search down until you find this instruction

0007ffd`7caae63a f00fb137        lock cmpxchg dword ptr [rdi],esi

This is the "compare and swap" instruction called cmpxchg on Intel CPUs. In our code we actually call InterlockedCompareExchange() but this is a compiler "intrinsic" so not a call into any DLL. It gets translated into this intruction

8. Now look down further to see the "backoff" code. You will see something like this

00007ffd`7caae696 ff1584044503    call    qword ptr [sqlmin!_imp_?BackoffSpinlockBaseIEAAXAEAVSpinInfo (00007ffd`7fefeb20)]

Now this looks odd but is an example of a call to a function that is part of a DLL referenced in something called an Import Address Table (IAT). And 00007ffd`7fefeb20 is the reference to the location in the table where SpinLockBase::Backoff exists.

dq 00007ffd`bf2e1ae0

You get this

00007ffd`7fefeb20  00007ffd`bf2e1ae0 00007ffd`bf2d3d00
00007ffd`7fefeb30  00007ffd`bf2d1220 00007ffd`bf34b350
00007ffd`7fefeb40  00007ffd`bf2ea4b0 00007ffd`bf33bac0
00007ffd`7fefeb50  00007ffd`bf2fc930 00007ffd`bf2fc870
00007ffd`7fefeb60  00007ffd`bf2fd2e0 00007ffd`bf2d8d80
00007ffd`7fefeb70  00007ffd`bf3be730 00007ffd`bf3bfba0
00007ffd`7fefeb80  00007ffd`bf3bfca0 00007ffd`bf3bf7c0
00007ffd`7fefeb90  00007ffd`bf2e3820 00007ffd`bf2e2160

and that first value 00007ffd`bf2e1ae0 is the pointer to the function SpinlockBase::Backoff

ln 00007ffd`bf2e1ae0

sqldk!SpinlockBase::Backoff

NOTE: An easier way to see the function calls in this routine is through the uf command with the /c parameter like this:

uf /c 00007ffd`7caae500

sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff (00007ffd`7caae500)
  sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff+0xbb (00007ffd`7caae5b3):
    call to sqldk!SpinlockStat::GetSpins (00007ffd`bf2d8d60)
  sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff+0xce (00007ffd`7caae5c6):
    call to sqldk!SpinlockStat::GetCollisions (00007ffd`bf2d8d40)
  sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff+0x163 (00007ffd`7caae696):
    call to sqldk!SpinlockBase::Backoff (00007ffd`bf2e1ae0)
  sqlmin!Spinlock<129,7,1>::SpinToAcquireWithExponentialBackoff+0x3f (00007ffd`7cd56301):
    call to sqldk!SystemThread::MakeMiniSOSThread (00007ffd`bf2f4c00)








