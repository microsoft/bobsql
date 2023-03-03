# Demo for the new query_abort Extended Event in SQL Server 2022

This is a demonstration for the new query_abort Extended Event in SQL Server 2022.

## Setup

1. Install SQL Server 2022 (Any edition)
2. Install the latest release of SQLCallStackResolver from https://github.com/microsoft/SQLCallStackResolver.
3. Run the xe.sql script to create and start and Extended Events session.

## Reproduce a query abort by cancelling a running query

1. Right click the new Extended Events session and select Watch Live Data.
2. Run the script repro.sql. Use SSMS to cancel the query a few seconds after it has run.
3. You should see two events have fired: query_abort and then attention (Note: You may see several attention events appear. Find the one that has the same session_id and sql_text as query_abort).

## Analyze the call stack differences for the cancel between query_abort and attention events

1. Launch SQLCallStackResolver.exe
2. Copy the callstack_rva cell from XEvent and paste this into left frame window
3. Paste into the Path to PDBs field the following

`srv*https://msdl.microsoft.com/download/symbols`

Note: If you want to cache symbols you can by creating a directory called c:\symbols (or whatever directory you want) and using this string instead:

`srv*c:\symbols*https://msdl.microsoft.com/download/symbols`

4. Click Step 3: Resolve callstacks

The callstack should look something like this

```xml
00 sqllang!XeSqlPkg::CollectSessionIdActionInvoke
01 sqllang!XeSqlPkg::query_abort::Publish
02 sqllang!CBatch::ProduceAbortEvent
03 sqllang!CBatch::SetAbort
04 sqllang!attention_handler
05 sqllang!TDSSNIClient::ReadHandler
06 sqllang!SNIReadDone
07 SqlDK!SOS_Node::ListenOnIOCompletionPort
08 SqlDK!SOS_Task::Param::Execute
09 SqlDK!SOS_Scheduler::RunTask
0a SqlDK!SOS_Scheduler::ProcessTasks
0b SqlDK!Worker::EntryPoint
0c SqlDK!ThreadScheduler::RunWorker
0d SqlDK!SystemThreadDispatcher::ProcessWorker
0e SqlDK!SchedulerManager::ThreadEntryPoint
0f kernel32!BaseThreadInitThunk
10 ntdll!RtlUserThreadStart
```

This callstack shows that a "attention" TDS packet received from the client to cancel the query.

Now do the same process for the task_callstack_rva field from the query_abort event. The stack should look something like this (depending on when you hit cancel):

```xml
00 sqlmin!CValHashCachedSwitch::GetDataX
01 sqlmin!CValHashCachedSwitch::GetDataX
02 sqlmin!CValHashCachedSwitch::GetDataX
03 SqlTsEs!CEsExec::GeneralEval
04 sqllang!CXStmtQuery::ErsqExecuteQuery
05 sqllang!CXStmtSelect::XretExecute
06 sqllang!CExecStmtLoopVars::ExecuteXStmtAndSetXretReturn
07 sqllang!CMsqlExecContext::ExecuteStmts<1,1>
08 sqllang!CMsqlExecContext::FExecute
09 sqllang!CSQLSource::Execute
0a sqllang!process_request
0b sqllang!process_commands_internal
0c sqllang!process_messages
0d SqlDK!SOS_Task::Param::Execute
0e SqlDK!SOS_Scheduler::RunTask
0f SqlDK!SOS_Scheduler::ProcessTasks
10 SqlDK!Worker::EntryPoint
11 SqlDK!ThreadScheduler::RunWorker
12 SqlDK!SystemThreadDispatcher::ProcessWorker
13 SqlDK!SchedulerManager::ThreadEntryPoint
14 kernel32!BaseThreadInitThunk
15 ntdll!RtlUserThreadStart
```

These two sequences mean a query was running but the client application who sent the query sent an attention to the server so this is most likely a long-running query that was cancelled.

5. Copy the callstack_rva cell from the attention event, paste and overwrite in the left frame, and select Step 3: Resolve callstacks

```xml
00 sqllang!XeSqlPkg::CollectSessionIdActionInvoke
01 sqllang!XeSqlPkg::CollectSqlText<XE_ActionForwarder>
02 sqllang!XeSqlPkg::CollectSqlTextActionInvoke
03 sqllang!XeSqlPkg::attention::Publish
04 sqllang!attention_trace
05 sqllang!process_commands_internal
06 sqllang!process_messages
07 SqlDK!SOS_Task::Param::Execute
08 SqlDK!SOS_Scheduler::RunTask
09 SqlDK!SOS_Scheduler::ProcessTasks
0a SqlDK!Worker::EntryPoint
0b SqlDK!ThreadScheduler::RunWorker
0c SqlDK!SystemThreadDispatcher::ProcessWorker
0d SqlDK!SchedulerManager::ThreadEntryPoint
0e kernel32!BaseThreadInitThunk
0f ntdll!RtlUserThreadStart
```

This callstack shows essentially the same thing except it is recorded after the query is aborted (which is why attention has a duration). Also the attention event does not have by default the input buffer (if a query was running when the abort occurred).

## Reproduce a query abort due to a query timeout

1. Clear the Watch Live Data XEvent session data
2. Run the script ddl.sql in master
3. Run the following command from the command prompt (The -t2 says user a query timeout of 2 seconds)

`sqlcmd -E -Q"select * from tab with (holdlock);" -dmaster -t2`

This should come back to the command prompt with a Timeout Expired message

4. In the XEvent Watch Live data you see the input buffer for the SELECT statement.
5. Using the same techniques as above, copy and paste the new tsql_callstack_rva value into SQLCallStackResolver.
6. Your new stack should look like this

```xml
00 ntdll!NtWaitForSingleObject
01 kernelbase!WaitForSingleObjectEx
02 SqlDK!SOS_Scheduler::SwitchContext
03 SqlDK!SOS_Scheduler::SuspendNonPreemptive
04 SqlDK!WaitableBase::Wait
05 sqlmin!LockOwner::Sleep
06 sqlmin!lck_lockInternal
07 sqlmin!lck_lockPartitionedAll
08 sqlmin!LockAndCheckState
09 sqlmin!GetHoBtLockInternal
0a sqlmin!HeapDataSetSession::WakeUpInternal
0b sqlmin!DatasetSession::WakeUp
0c sqlmin!DatasetSession::Create
0d sqlmin!RowsetNewSS::WakeUpInternal
0e sqlmin!RowsetNewSS::WakeUp
0f sqlmin!CQScanRowsetNew::WakeUpRowset
10 sqlmin!CQScanRowsetNew::OpenHelper
11 sqlmin!CQScanTableScanNew::Open
12 sqlmin!CQueryScan::StartupQuery
13 sqllang!CXStmtQuery::SetupQueryScanAndExpression
14 sqllang!CXStmtQuery::InitForExecute
15 sqllang!CXStmtQuery::ErsqExecuteQuery
16 sqllang!CXStmtSelect::XretExecute
17 sqllang!CExecStmtLoopVars::ExecuteXStmtAndSetXretReturn
18 sqllang!CMsqlExecContext::ExecuteStmts<1,1>
19 sqllang!CMsqlExecContext::FExecute
1a sqllang!CSQLSource::Execute
1b sqllang!process_request
1c sqllang!process_commands_internal
1d sqllang!process_messages
1e SqlDK!SOS_Task::Param::Execute
<frame id="31" address="0xA000" />
<frame id="32" address="0xDEABF84C8" />
```

I can see that the query was blocked at the time of the abort which likely means a query timeout occurred from the client application due to a blocking problem.

7. Rollback the transaction from **ddl.sql** and close out the connection.

## Reproduce a query abort when terminating a session

This is where query_abort can help us find out why a query aborted if not a query timeout or explicit cancel.

1. Select Clear Data in the SSMS Watch Live Data Window
2. Open a new query window in SSMS.
3. Run repro.sql again. Note the session_id value.
4. In the query window from step #2 execute the following command:

`KILL <session_id>`

session_is is the value collected from step #3

5. Observe the data in the Watch Live Data window

You will only see a query_abort event this time
Notice the session_id is different than the session_id (Action).

The session_id (Action) is the session that caused the "query_abort" which is the session that executed the T-SQL KILL statement.

6. Observe call stack

Copy the callstack_rva value and paste ito the left frame of SQLCallStackResolver. Click Step 3 to Resolve callstacks. The results should look like following:

```xml
00 sqllang!XeSqlPkg::CollectSessionIdActionInvoke
01 sqllang!XeSqlPkg::query_abort::Publish
02 sqllang!CBatch::ProduceAbortEvent
03 sqllang!CBatch::SetAbort
04 sqllang!CSession::FKillSessionNoSuspendInternal
05 sqllang!CStmtKillSpid::FNukeSpid
06 sqllang!CStmtKillSpid::XretExecuteKillInternal
07 sqllang!CStmtKillSpid::XretExecuteKill
08 sqllang!CExecStmtLoopVars::ExecuteXStmtAndSetXretReturn
09 sqllang!CMsqlExecContext::ExecuteStmts<1,1>
0a sqllang!CMsqlExecContext::FExecute
0b sqllang!CSQLSource::Execute
0c sqllang!process_request
0d sqllang!process_commands_internal
0e sqllang!process_messages
0f SqlDK!SOS_Task::Param::Execute
10 SqlDK!SOS_Scheduler::RunTask
11 SqlDK!SOS_Scheduler::ProcessTasks
12 SqlDK!Worker::EntryPoint
13 SqlDK!ThreadScheduler::RunWorker
14 SqlDK!SystemThreadDispatcher::ProcessWorker
15 SqlDK!SchedulerManager::ThreadEntryPoint
16 kernel32!BaseThreadInitThunk
17 ntdll!RtlUserThreadStart
```
This is the callstack of the session that issues the KILL statement to abort the running query from the other session. So no "attention" was received to abort the query.
