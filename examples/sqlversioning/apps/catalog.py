"""Presenter-paced SQL Server 2025 labs; importing this module never connects.

The backend must use autocommit connections, preserve explicit transactions on
sessions 1/2, split standalone GO, and allow a blocked read to run asynchronously.
End demo must close both sessions before requires_clean_sessions steps. Do not
run an entire scenario as a batch. DBCC formats and cleaner timing are internal
implementation details, not assertions about measured results.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEMO_FOLDERS = {
    "0": "demo0-setup",
    "1": "demo1-blocking",
    "2": "demo2-rcsi-snapshot",
    "3": "demo3-version-store",
    "4": "demo4-adr-pvs",
}
PRIMARY = "starswillwinthecup"
EAGLES = "eaglesdontfly"
COWBOYS = "howboutthemcowboys"


def _source(filename):
    return (ROOT / filename).read_text(encoding="utf-8-sig")


def _statement(filename, beginning):
    """Reuse the original wide-column values and seed SELECTs verbatim."""
    text = _source(filename)
    start = text.index(beginning)
    return text[start:text.index(";", start) + 1]


def _step(scenario, key, title, session, sql, explanation, **options):
    return dict(id=f"{scenario}-{key}", title=title, session=session,
                sql=sql.strip(), explanation=explanation, **options)


def _scenario(identifier, title, description, files):
    return dict(
        id=identifier, title=title,
        description=("PREREQUISITE: Run Demo 0 — Setup first. Before configuration, use "
                     "End demo to rollback and CLOSE both sessions, including "
                     "any asynchronous request. Never configure with a live "
                     "snapshot or writer. Run the steps in order, one click at "
                     "a time; finish cleanup before switching scenarios. " + description),
        source_files=files, steps=[],
    )


def _add(scenario, key, title, session, sql, explanation, **options):
    scenario["steps"].append(_step(scenario["id"], key, title, session, sql,
                                  explanation, **options))


def _config(scenario, key="configure", *, db=PRIMARY, adr=False, rcsi=True,
            snapshot=True):
    _add(scenario, key, "End demo first — configure database", "admin", f"""
USE master;
ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE [{db}] SET OPTIMIZED_LOCKING = OFF;
ALTER DATABASE [{db}] SET ACCELERATED_DATABASE_RECOVERY = {'ON' if adr else 'OFF'};
ALTER DATABASE [{db}] SET READ_COMMITTED_SNAPSHOT {'ON' if rcsi else 'OFF'};
ALTER DATABASE [{db}] SET ALLOW_SNAPSHOT_ISOLATION {'ON' if snapshot else 'OFF'};
GO
ALTER DATABASE [{db}] SET MULTI_USER;
SELECT name, is_read_committed_snapshot_on AS RCSI,
       snapshot_isolation_state_desc AS SnapshotIsolation,
       is_accelerated_database_recovery_on AS ADR,
       is_optimized_locking_on AS OptimizedLocking
FROM sys.databases WHERE name = N'{db}';
""", "REQUIRED: click End demo immediately before this step so both persistent "
         "connections are CLOSED. This changes lab database options and can "
         "terminate other users. Admin remains in master. Optimized locking is "
         "disabled to make the original lock/version evidence comparable.",
         dangerous=True, requires_clean_sessions=True)


def _reset(scenario, account=42, value="100.00", table="Accounts", key="reset"):
    _add(scenario, key, "Reset the starting balance", "1", f"""
USE [{PRIMARY}];
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE dbo.{table} SET Balance = {value} WHERE AccountId = {account};
SELECT N'Starting committed balance' AS Observation, AccountId, Balance
FROM dbo.{table} WHERE AccountId = {account};
""", "Destructive lab reset, not a production operation. Run only after "
         "configuration and before opening the reader/writer transactions. "
         "This explicit baseline makes repeated presentations comparable.",
         dangerous=True)


def _balance(account=42, label="Current committed balance", table="Accounts",
             hint=""):
    label = label.replace("'", "''")
    return f"""USE [{PRIMARY}];
SELECT N'{label}' AS Observation, AccountId, Balance
FROM dbo.{table} {hint} WHERE AccountId = {account};"""


def _read(scenario, key, label, session="1", account=42, table="Accounts",
          hint="", explanation="Compare this sampled balance with the labeled baseline."):
    _add(scenario, key, label, session,
         _balance(account, label, table, hint), explanation)


def _snapshot(scenario, key="snapshot", account=42, table="Accounts", db=PRIMARY,
              query=None):
    query = query or (f"SELECT N'Snapshot baseline' AS Observation, AccountId, "
                      f"Balance FROM dbo.{table} WHERE AccountId = {account};")
    _add(scenario, key, "Open and establish the snapshot", "1", f"""
USE [{db}];
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
{query}
""", "The first data access establishes the snapshot, not BEGIN TRAN alone. "
         "Leave session 1 open. Later writer steps run on session 2 in "
         "autocommit; monitoring must not create another pinned transaction.")


def _release(scenario, key="release", session="1", rollback=False):
    _add(scenario, key, "Rollback and restore READ COMMITTED" if rollback else
         "Commit and restore READ COMMITTED", session, f"""
IF @@TRANCOUNT > 0 {'ROLLBACK' if rollback else 'COMMIT'};
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
""", "Release this session's transaction/watermark explicitly. A conflict may "
         "already have aborted it, so the transaction-count guard is intentional.")


def _cleanup(scenario):
    for session in ("1", "2"):
        _add(scenario, f"cleanup-{session}", f"Clean session {session}", session, """
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET STATISTICS IO OFF;
USE master;
SELECT @@SPID AS SessionId, @@TRANCOUNT AS RemainingTransactions;
""", "Finish/cancel any asynchronous request first. Roll back leftover work "
             "and reset connection state. Finally click End demo to CLOSE both "
             "connections before the next configuration or destructive setup.")


TEMPDB_SPACE = """
SELECT DB_NAME(database_id) AS [Database], reserved_page_count AS VersionPages,
       reserved_space_kb AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id IN (DB_ID(N'starswillwinthecup'),
                      DB_ID(N'eaglesdontfly'), DB_ID(N'howboutthemcowboys'));
SELECT SUM(version_store_reserved_page_count) AS VersionStorePages,
       SUM(version_store_reserved_page_count) * 8 AS VersionStoreKB,
       SUM(total_page_count) AS TotalPages
FROM tempdb.sys.dm_db_file_space_usage;
"""
ACTIVE = """
SELECT ast.session_id, ast.transaction_id, ast.elapsed_time_seconds,
       ast.transaction_sequence_num AS SnapshotXSN,
       ast.first_snapshot_sequence_num,
       ast.max_version_chain_traversed AS MaxChainHops,
       ast.average_version_chain_traversed AS AvgChainHops,
       DB_NAME(es.database_id) AS SessionDatabase, es.program_name
FROM sys.dm_tran_active_snapshot_database_transactions ast
JOIN sys.dm_exec_sessions es ON ast.session_id = es.session_id;
"""
TEMPDB_RECORDS = f"""
SELECT transaction_sequence_num AS XSN, version_sequence_num AS SeqInChain,
       DB_NAME(database_id) AS [Database], rowset_id, status,
       min_length_in_bytes, record_length_first_part_in_bytes AS RecordBytes1st,
       record_image_first_part
FROM sys.dm_tran_version_store
WHERE database_id = DB_ID(N'{PRIMARY}')
ORDER BY transaction_sequence_num DESC;
"""


def _tempdb(scenario, key="versions", title="Measure tempdb versions and snapshot holders"):
    _add(scenario, key, title, "admin", "USE master;\n" + TEMPDB_SPACE + ACTIVE,
         "Read-only monitoring on an autocommit admin connection. Values are "
         "live measurements, not promised counts. Freed tempdb pages do not "
         "imply that the physical files shrink. Re-run after a presenter-paced "
         "pause to observe asynchronous cleanup; other workloads may retain versions.")


def _pvs_sql(db=PRIMARY, records=True):
    sql = f"""
USE [{db}];
SELECT DB_NAME(database_id) AS [Database],
       persistent_version_store_size_kb AS PVS_Size_KB,
       online_index_version_store_size_kb AS OnlineIndexPVS_KB,
       current_aborted_transaction_count AS AbortedTransactionCount,
       min_transaction_timestamp AS XTS_Floor,
       offrow_version_cleaner_start_time AS OffRowCleanerStart,
       offrow_version_cleaner_end_time AS OffRowCleanerEnd,
       aborted_version_cleaner_start_time AS AbortedCleanerStart,
       aborted_version_cleaner_end_time AS AbortedCleanerEnd
FROM sys.dm_tran_persistent_version_store_stats WHERE database_id = DB_ID();
"""
    if records:
        sql += """
SELECT COALESCE(OBJECT_NAME(p.object_id), N'(system)') AS TableName,
       COUNT_BIG(*) AS ObservedOffRowRecords
FROM sys.dm_tran_persistent_version_store pvs
LEFT JOIN sys.partitions p ON pvs.rowset_id = p.hobt_id
GROUP BY p.object_id;
"""
    return sql


def _pvs(scenario, key, title="Measure PVS and cleaner timestamps", db=PRIMARY):
    _add(scenario, key, title, "2", _pvs_sql(db),
         "Session 2 must have no explicit transaction: the monitor uses "
         "autocommit so it does not pin cleanup. PVS DMV rows are off-row "
         "records only; in-row versions are not counted here. Actual sizes, "
         "counts and timestamps depend on page layout and asynchronous cleanup.")


def _pvs_records(scenario, key, table="Accounts"):
    _add(scenario, key, "Inspect actual off-row version links", "2", f"""
USE [{PRIMARY}];
SELECT pvs.xdes_ts_push AS PushTS, pvs.xdes_ts_tran AS TranTS,
       pvs.seq_num AS SeqNum, pvs.min_len AS MinLen, pvs.rowset_id AS RowsetId,
       pvs.prev_row_in_chain AS PrevRowInChain, pvs.row_version AS RowVersion
FROM sys.dm_tran_persistent_version_store pvs
WHERE pvs.rowset_id IN
    (SELECT hobt_id FROM sys.partitions
     WHERE object_id = OBJECT_ID(N'dbo.{table}') AND index_id IN (0,1));
""", "Inspect the returned raw row_version and prev_row_in_chain values, as "
         "in the source scripts. Do not label an intended update count as a "
         "measured chain length. A database-wide PVS count is not this row's chain.")


def _page(scenario, key, table="Accounts", db=PRIMARY, account=42):
    _add(scenario, key, f"Page viewer — {table} row {account}", "admin", f"""
USE master;
DECLARE @db int = DB_ID(N'{db}'), @file int, @page int, @slot int;
SELECT @file = loc.file_id, @page = loc.page_id, @slot = loc.slot_id
FROM [{db}].dbo.[{table}] WITH (NOLOCK)
CROSS APPLY sys.fn_PhysLocCracker(%%physloc%%) AS loc
WHERE {'GameId' if table == 'GameStats' else 'AccountId'} = {account};
SELECT N'Physical row location (not a chain count)' AS Observation,
       @db AS DatabaseId, @file AS FileId, @page AS PageId, @slot AS SlotId;
IF @page IS NOT NULL
BEGIN
    DBCC TRACEON(3604);
    DBCC PAGE(@db, @file, @page, 3) WITH TABLERESULTS;
    DBCC TRACEOFF(3604);
END;
""", "Open the formatted page viewer in a new tab, then click View Page. "
         "The database, table and row are prefilled. Inspect the highlighted "
         "version tag, XSN and pointer; return here and click Next to continue. "
         "Opening the viewer does not run SQL or close the demo sessions. "
         "Use View Page again to refresh the evidence after each update. "
         "Internal page formats and cleanup timing vary by build.",
         viewer=dict(kind="adr" if scenario["id"].startswith("4") else "tempdb",
                     database=db, table_name=table, find_row=str(account)))


def _force_cleanup(scenario, key, db=PRIMARY):
    _add(scenario, key, "Request PVS cleanup", "2", f"""
USE [{db}];
EXEC sys.sp_persistent_version_cleanup @dbname = N'{db}';
""", "Diagnostic/manual cleanup request from the original lab. Session 2 "
         "must be autocommit, not another snapshot. This cannot bypass a pinned "
         "watermark and does not guarantee immediate zero PVS.",
         dangerous=True)


def _skips(scenario, key, db=PRIMARY):
    _add(scenario, key, "Inspect cleaner skip reasons and idle transactions", "2", f"""
USE [{db}];
SELECT pvs_off_row_page_skipped_low_water_mark AS SkippedLowWatermark,
       pvs_off_row_page_skipped_oldest_active_xdesid AS SkippedOldestActiveXdes,
       pvs_off_row_page_skipped_min_useful_xts AS SkippedMinUsefulXts,
       pvs_off_row_page_skipped_oldest_snapshot AS SkippedOldestSnapshot
FROM sys.dm_tran_persistent_version_store_stats WHERE database_id = DB_ID();
{ACTIVE}
SELECT session_id, program_name, login_name, open_transaction_count,
       last_request_end_time,
       DATEDIFF(SECOND, last_request_end_time, GETDATE()) AS IdleSeconds
FROM sys.dm_exec_sessions
WHERE open_transaction_count > 0 AND is_user_process = 1
ORDER BY last_request_end_time;
""", "Compare cumulative skip counters before/after cleanup attempts; a "
         "nonzero counter alone does not identify today's blocker. Idle pooled "
         "connections with transactions can pin versions. The source 4d's "
         "per-database-isolation claim is not assumed: 4c tests instance-wide XTS.")


def _write_balance(scenario, key, value, account=42, session="2", begin=False):
    _add(scenario, key, f"{'Hold uncommitted' if begin else 'Commit'} balance {value}",
         session, f"""
USE [{PRIMARY}];
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
{'BEGIN TRAN;' if begin else ''}
UPDATE dbo.Accounts SET Balance = {value}, LastUpdated = SYSUTCDATETIME()
WHERE AccountId = {account};
SELECT N'{"Writer uncommitted balance" if begin else "Writer committed balance"}'
       AS Observation, AccountId, Balance FROM dbo.Accounts WHERE AccountId = {account};
""", "Leave this explicit writer transaction OPEN until its commit/rollback "
         "step." if begin else "Session 2 autocommit makes this update a separate "
         "committed transaction, while the session 1 snapshot remains unchanged.")


SETUP_INVENTORY_SQL = "\n".join(f"""
IF DB_ID(N'{database}') IS NOT NULL
BEGIN
    SELECT N'{database}' AS DatabaseName, s.name AS SchemaName,
           t.name AS TableName, SUM(p.rows) AS ApproximateRows
    FROM [{database}].sys.tables t
    JOIN [{database}].sys.schemas s ON s.schema_id = t.schema_id
    JOIN [{database}].sys.partitions p ON p.object_id = t.object_id
    WHERE p.index_id IN (0,1)
    GROUP BY s.name, t.name ORDER BY s.name, t.name;
END;
""" for database in (PRIMARY, EAGLES, COWBOYS))

S0 = _scenario("0", "Prepare the lab", "DESTRUCTIVE: setup drops and recreates "
               "ALL THREE databases and loads large tables. Obtain approval "
               "before selecting setup. Readiness does not execute setup.",
               ["demo0-setup/demo0-setup.sql"])
_add(S0, "setup", "Run setup", "admin",
     _source("demo0-setup/demo0-setup.sql") + "\nGO\nUSE master;\n" + SETUP_INVENTORY_SQL,
     "APPROVAL REQUIRED: End demo first. The embedded ORIGINAL setup drops "
     "starswillwinthecup, eaglesdontfly and howboutthemcowboys, "
     "terminates their users and reseeds all data. It can take substantial "
     "time/disk/log space. No setup runs at import or during readiness.",
     dangerous=True, requires_clean_sessions=True)
_add(S0, "readiness", "Read-only readiness and object inventory", "admin", f"""
USE master;
SELECT @@VERSION AS ServerVersion,
       SERVERPROPERTY('ProductMajorVersion') AS ProductMajorVersion,
       IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin;
SELECT name, state_desc, is_read_committed_snapshot_on AS RCSI,
       snapshot_isolation_state_desc AS SnapshotIsolation,
       is_accelerated_database_recovery_on AS ADR,
       is_optimized_locking_on AS OptimizedLocking
FROM sys.databases WHERE name IN (N'{PRIMARY}', N'{EAGLES}', N'{COWBOYS}');
""" + SETUP_INVENTORY_SQL, "SQL Server 2025 (major 17), DBCC/DMV/database-alter permissions and "
     "all three online databases are prerequisites. Missing databases are "
     "reported without creating anything. Catalog row estimates are not counts "
     "of versions. This is not a substitute for tools/check-readiness.ps1.")

S1 = _scenario("1", "Blocking and dirty reads", "Locking READ COMMITTED blocks; "
               "NOLOCK can expose a value that is later rolled back.",
               ["demo1-blocking/demo1-blocking-session1.sql", "demo1-blocking/demo1-blocking-session2.sql"])
_config(S1, rcsi=False, snapshot=False)
_reset(S1, 1)
_add(S1, "writer", "Hold writer X lock (100 → 200)", "1", f"""
USE [{PRIMARY}];
BEGIN TRAN;
UPDATE dbo.Accounts SET Balance = Balance + 100.00,
    LastUpdated = SYSUTCDATETIME() WHERE AccountId = 1;
SELECT N'Writer uncommitted balance' AS Observation, AccountId, Balance
FROM dbo.Accounts WHERE AccountId = 1;
SELECT resource_type, resource_description, request_mode, request_status
FROM sys.dm_tran_locks WHERE request_session_id = @@SPID
AND resource_type IN (N'KEY', N'RID', N'PAGE');
""", "The writer owns an X lock. Do not commit yet.")
_read(S1, "blocked", "Locking read — start asynchronously", "2", 1,
      explanation="Start asynchronously: this SELECT waits for the writer. "
      "Do not wait for it to finish before selecting the next steps.")
_add(S1, "waits", "Observe the blocked reader", "admin", """
USE master;
SELECT session_id AS WaitingSession, blocking_session_id AS BlockingSession,
       wait_type, wait_time, last_wait_type
FROM sys.dm_exec_requests WHERE blocking_session_id <> 0;
""", "The monitor is a third, autocommit connection, not the blocked session 2.")
_release(S1, "writer-commit", "1")
_read(S1, "committed", "Reader sees committed 200", "2", 1,
      explanation="Wait for the asynchronous read to finish first; session 2 "
      "cannot run another command while its SELECT is active.")
_add(S1, "dirty-writer", "Hold a value that will never commit", "1", f"""
USE [{PRIMARY}];
BEGIN TRAN;
UPDATE dbo.Accounts SET Balance = Balance + 999999.00,
    LastUpdated = SYSUTCDATETIME() WHERE AccountId = 1;
SELECT N'Writer uncommitted balance' AS Observation, AccountId, Balance
FROM dbo.Accounts WHERE AccountId = 1;
""", "The uncommitted value is 1000199.00. Keep the transaction open.")
_read(S1, "nolock", "NOLOCK dirty balance", "2", 1, hint="WITH (NOLOCK)",
      explanation="Run BEFORE rollback: NOLOCK may return 1000199.00 even "
      "though no transaction will commit that value. It is not a safe fix.")
_add(S1, "dirty-rollback", "Rollback and restore READ COMMITTED", "1", f"""
USE [{PRIMARY}];
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT N'Writer balance after rollback' AS Observation, AccountId, Balance
FROM dbo.Accounts WHERE AccountId = 1;
""", "Roll back the dirty change and return the restored balance of 200 "
         "from the writer's connection.")
_read(S1, "clean", "Clean balance after rollback (200)", "2", 1)
_cleanup(S1)

S2A = _scenario("2a", "RCSI reads without waiting", "Compare RCSI with the "
                "READCOMMITTEDLOCK opt-in; the writer must commit after the "
                "blocking hint read is started asynchronously.",
                ["demo2-rcsi-snapshot/demo2a-rcsi-session1.sql", "demo2-rcsi-snapshot/demo2a-rcsi-session2.sql"])
_config(S2A)
_reset(S2A, 1)
_write_balance(S2A, "writer", "Balance + 500.00", 1, session="1", begin=True)
_read(S2A, "rcsi", "RCSI committed before-image (100)", "2", 1,
      explanation="READ COMMITTED uses statement versions: the writer's "
      "uncommitted 600 is not visible and the read should not wait.")
_tempdb(S2A)
_read(S2A, "hint-blocked", "READCOMMITTEDLOCK — start asynchronously", "2", 1,
      hint="WITH (READCOMMITTEDLOCK)",
      explanation="This hint opts back into S locks. Start asynchronously, "
      "then select the writer commit while this read is waiting.")
_release(S2A, "writer-commit", "1")
_read(S2A, "after", "Latest committed balance (600)", "2", 1,
      explanation="Wait for the hinted read to finish before using session 2 again.")
_cleanup(S2A)

S2B = _scenario("2b", "Statement versus transaction snapshots", "RCSI reads "
                "change within one transaction; SNAPSHOT rereads remain frozen.",
                ["demo2-rcsi-snapshot/demo2b-rcsi-vs-snapshot-session1.sql",
                 "demo2-rcsi-snapshot/demo2b-rcsi-vs-snapshot-session2.sql"])
_config(S2B)
_reset(S2B, 200, "1000.00")
_add(S2B, "rcsi-first", "RCSI transaction — first read (1000)", "1", f"""
USE [{PRIMARY}];
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRAN;
SELECT N'RCSI first statement' AS Observation, AccountId, Balance
FROM dbo.Accounts WHERE AccountId = 200;
""", "RCSI does not make all statements in this transaction share a snapshot.")
_write_balance(S2B, "rcsi-writer", "2000.00", 200)
_read(S2B, "rcsi-second", "RCSI second statement (2000)", account=200)
_release(S2B, "rcsi-commit")
_reset(S2B, 200, "1000.00", key="snapshot-reset")
_snapshot(S2B, account=200)
_write_balance(S2B, "snapshot-writer", "2000.00", 200)
_read(S2B, "snapshot-second", "Snapshot reread (still 1000)", account=200)
_release(S2B)
_read(S2B, "outside", "Outside snapshot (2000)", account=200)
_cleanup(S2B)

S2C = _scenario("2c", "Snapshot update conflict", "Error 3960 means retry the "
                "whole transaction, not silently retry its UPDATE.",
                ["demo2-rcsi-snapshot/demo2c-snapshot-conflict-session1.sql",
                 "demo2-rcsi-snapshot/demo2c-snapshot-conflict-session2.sql"])
_config(S2C)
_reset(S2C, 100)
_snapshot(S2C, account=100)
_write_balance(S2C, "competitor", "Balance + 999.00", 100)
_add(S2C, "conflict", "Expected error 3960 — stale snapshot UPDATE", "1", f"""
USE [{PRIMARY}];
UPDATE dbo.Accounts SET Balance = Balance + 50.00 WHERE AccountId = 100;
""", "Session 2 committed 1099 after our 100 snapshot. The UPDATE must "
     "report SQL error 3960. Stop here if the expected error does not occur.",
     expected_error=3960)
_release(S2C, rollback=True)
_read(S2C, "actual", "Competitor's committed balance (1099)", account=100)
_reset(S2C, 100, key="restore")
_cleanup(S2C)

S2D = _scenario("2d", "Foreign-key shared locks under RCSI", "An Orders insert "
                "still validates its Accounts parent with a shared key lock.",
                ["demo2-rcsi-snapshot/demo2d-fk-slock.sql"])
_config(S2D)
_reset(S2D, 1)
_add(S2D, "insert", "Insert an order — leave FK validation locks held", "1", f"""
USE [{PRIMARY}];
DROP TABLE IF EXISTS #FkInserted;
CREATE TABLE #FkInserted (OrderId int NOT NULL);
BEGIN TRAN;
INSERT INTO dbo.Orders (AccountId, Amount)
OUTPUT inserted.OrderId INTO #FkInserted VALUES (1, 500.00);
SELECT request_session_id, resource_type, resource_description, request_mode
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID() AND request_mode = N'S'
  AND resource_type = N'KEY';
""", "The source's shared KEY lock proves RCSI does not eliminate FK "
     "validation locks. The transaction remains open. A session-local identity "
     "capture supports exact cleanup after demonstrating COMMIT.", dangerous=True)
_release(S2D, "commit-insert")
_add(S2D, "remove-insert", "Remove only this presentation's inserted order", "1", f"""
USE [{PRIMARY}];
DELETE o FROM dbo.Orders o JOIN #FkInserted i ON i.OrderId = o.OrderId;
DROP TABLE #FkInserted;
""", "The inserted identity was captured in a session-local temporary table. "
     "Remove exactly that order after demonstrating COMMIT; existing orders "
     "are untouched. End demo is still required before new configuration.",
     dangerous=True)
_cleanup(S2D)

S2E = _scenario("2e", "FK scan conflict and indexed fix", "The random original "
                "seed must be normalized: Order 1 is child-free and Item 1 "
                "belongs to Order 2. Backups restore those relationships at "
                "the end. A 547 FK violation is NOT the expected 3960 result.",
                ["demo2-rcsi-snapshot/demo2e-fk-scan-conflict-session1.sql",
                 "demo2-rcsi-snapshot/demo2e-fk-scan-conflict-session2.sql"])
_config(S2E)
_add(S2E, "fk-reset", "Prepare deterministic FK scan trap (remove fix index)", "2", f"""
USE [{PRIMARY}];
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
IF NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderId = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderId = 2)
   OR NOT EXISTS (SELECT 1 FROM dbo.OrderItems WHERE ItemId = 1)
    THROW 50000, 'Run demo0: Orders 1/2 and Item 1 are required.', 1;
DROP INDEX IF EXISTS IX_OrderItems_OrderId ON dbo.OrderItems;
DROP TABLE IF EXISTS #FkOriginalItems;
SELECT ItemId, OrderId, Quantity INTO #FkOriginalItems
FROM dbo.OrderItems WHERE OrderId = 1 OR ItemId = 1;
UPDATE dbo.OrderItems SET OrderId = 2 WHERE OrderId = 1 OR ItemId = 1;
SELECT i.name AS IndexName, c.name AS ColumnName
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID(N'dbo.OrderItems');
SELECT N'Unrelated modifier baseline' AS Observation, ItemId, OrderId, Quantity
FROM dbo.OrderItems WHERE ItemId = 1;
SELECT COUNT(*) AS ChildrenOfDeleteTarget FROM dbo.OrderItems WHERE OrderId = 1;
""", "Destructive lab prerequisite: remove the fix index for repeatability. "
     "Original seed uses random child OrderIds, so without this normalization "
     "DELETE may instead fail with 547 (or Item 1 may not be unrelated). Keep "
     "session 2 connected: #FkOriginalItems is needed for final restoration.",
     dangerous=True)
_snapshot(S2E, query="SELECT TOP 1 OrderId FROM dbo.Orders;")
_add(S2E, "unrelated-update", "Modify the unrelated Item 1", "2", f"""
USE [{PRIMARY}];
UPDATE dbo.OrderItems SET Quantity = Quantity + 1 WHERE ItemId = 1;
SELECT N'Unrelated committed item' AS Observation, ItemId, OrderId, Quantity
FROM dbo.OrderItems WHERE ItemId = 1;
""", "A committed modification to Order 2's item, not the Order 1 being deleted.")
_add(S2E, "scan-conflict", "Expected 3960 — DELETE hits unrelated child scan", "1",
     f"USE [{PRIMARY}];\nDELETE FROM dbo.Orders WHERE OrderId = 1;",
     "Without an OrderId index, FK validation scans OrderItems and encounters "
     "the modified unrelated row. Expect 3960, not 547.", expected_error=3960)
_release(S2E, "scan-rollback", rollback=True)
_add(S2E, "index-fix", "Create the foreign-key index", "2", f"""
USE [{PRIMARY}];
CREATE NONCLUSTERED INDEX IX_OrderItems_OrderId ON dbo.OrderItems(OrderId);
""", "The original indexed fix allows a seek on the FK range. The failed "
     "snapshot must be rolled back before DDL; keep session 2's backup alive.",
     dangerous=True)
_snapshot(S2E, "indexed-snapshot", query="SELECT TOP 1 OrderId FROM dbo.Orders;")
_add(S2E, "indexed-unrelated-update", "Repeat unrelated item UPDATE with the index",
     "2", f"USE [{PRIMARY}];\nUPDATE dbo.OrderItems SET Quantity = Quantity + 1 "
     "WHERE ItemId = 1;", "Same competing change, now after the indexed snapshot.")
_add(S2E, "indexed-delete", "Indexed DELETE succeeds (do not commit)", "1",
     f"USE [{PRIMARY}];\nDELETE FROM dbo.Orders WHERE OrderId = 1;\n"
     "SELECT @@ROWCOUNT AS DeletedOrdersInThisTransaction;",
     "Order 1 has no children. The seek avoids unrelated Item 1 and should "
     "delete exactly one order without 3960. Roll it back next to preserve the seed.")
_release(S2E, "indexed-rollback", rollback=True)
_add(S2E, "restore-items", "Restore original FK seed; retain the indexed fix", "2", f"""
USE [{PRIMARY}];
UPDATE i SET OrderId = b.OrderId, Quantity = b.Quantity
FROM dbo.OrderItems i JOIN #FkOriginalItems b ON b.ItemId = i.ItemId;
DROP TABLE #FkOriginalItems;
""", "Restores original random relationships/quantities. The fix index remains "
     "by design, but the next scenario run explicitly drops it in its reset. "
     "If interrupted before restoration, run demo0 with approval.", dangerous=True)
_cleanup(S2E)

S3A = _scenario("3a", "Inside a tempdb version chain", "Present both RCSI's "
                "uncommitted before-image and three separately committed "
                "updates held by SNAPSHOT. Inspect pages and actual DMV hops.",
                ["demo3-version-store/demo3a-version-chain-session1.sql",
                 "demo3-version-store/demo3a-version-chain-session2.sql"])
_config(S3A)
_reset(S3A)
_page(S3A, "baseline-page")
_read(S3A, "baseline", "RCSI baseline (100)")
_write_balance(S3A, "rcsi-writer", "200.00", begin=True)
_page(S3A, "uncommitted-page")
_add(S3A, "raw-version", "Inspect raw tempdb before-images", "admin",
     "USE master;\n" + TEMPDB_RECORDS,
     "Original version-store DMV evidence. Actual rows may include other "
     "changes; do not claim a row count is this Account 42's chain length.")
_read(S3A, "before-image", "RCSI sees committed 100")
_release(S3A, "writer-commit", "2")
_read(S3A, "committed", "RCSI now sees 200")
_tempdb(S3A, "beat1-cleaner", "Pause, then observe tempdb cleanup")
_snapshot(S3A)
for number, value in enumerate(("300.00", "400.00", "500.00"), 1):
    _write_balance(S3A, f"chain-update-{number}", value)
    _page(S3A, f"chain-page-{number}")
_add(S3A, "hops-before", "Measure chain traversal before reread", "1", """
SELECT max_version_chain_traversed AS MaxChainHopsBefore,
       average_version_chain_traversed AS AvgChainHopsBefore
FROM sys.dm_tran_active_snapshot_database_transactions WHERE session_id = @@SPID;
""", "Capture this session's actual counters before the chain-walking read.")
_add(S3A, "chain-read", "Snapshot walks back to 200", "1",
     "SET STATISTICS IO ON;\n" + _balance(label="Snapshot held balance (200)") +
     "\nSET STATISTICS IO OFF;",
     "Three writes were intended; only measured DMV counters establish hops. "
     "STATISTICS IO may report messages separately, and exact IO is build/page dependent.")
_add(S3A, "hops-after", "Measure actual traversal after reread", "1", """
SELECT max_version_chain_traversed AS MaxChainHopsAfter,
       average_version_chain_traversed AS AvgChainHopsAfter
FROM sys.dm_tran_active_snapshot_database_transactions WHERE session_id = @@SPID;
""", "Compare measured before/after counters, not a fabricated constant of three.")
_tempdb(S3A, "held")
_release(S3A)
_read(S3A, "latest", "After snapshot — committed 500")
_tempdb(S3A, "released", "Pause, then measure reclaimed versions")
_cleanup(S3A)

S3B = _scenario("3b", "One forgotten snapshot, another database's cost",
                "Ten separate update waves in the victim database; observe "
                "actual tempdb growth and release the culprit's watermark.",
                ["demo3-version-store/demo3b-instance-wide-impact-session1.sql",
                 "demo3-version-store/demo3b-instance-wide-impact-session2.sql"])
_config(S3B, "configure-culprit", db=EAGLES)
_config(S3B, "configure-victim", db=COWBOYS)
_tempdb(S3B, "baseline")
_snapshot(S3B, db=EAGLES,
          query="SELECT TOP 1 Category, SuperBowlChances FROM dbo.ReportData;")
for number in range(1, 11):
    _add(S3B, f"wave-{number}", f"Victim committed update wave {number}", "2",
         f"USE [{COWBOYS}];\nUPDATE dbo.GameStats SET Yards = Yards + 1;",
         "One original full-table UPDATE, one autocommit transaction. Wide "
         "GameStats rows can consume substantial tempdb. This wave count is "
         "presenter intent, not a measured version-chain length.", dangerous=True)
    if number in (5, 10):
        _tempdb(S3B, f"measure-{number}")
_page(S3B, "victim-page", "GameStats", COWBOYS, 1)
_release(S3B)
_tempdb(S3B, "released", "Pause, then measure cleanup after culprit commits")
_add(S3B, "restore-yards", "Undo exactly the ten completed waves", "2",
     f"USE [{COWBOYS}];\nUPDATE dbo.GameStats SET Yards = Yards - 10;",
     "Run ONCE and only after all ten waves succeeded. If interrupted or a "
     "wave failed, do not guess: End demo and restore the approved demo0 seed.",
     dangerous=True)
_cleanup(S3B)

S3C = _scenario("3c", "Ghost records versus tempdb versions", "Original DELETE "
                "range 9901–10000 has randomly seeded FK dependencies. Back "
                "them up in session 2, temporarily remove them, then restore "
                "the exact original identities/relationships after the demo.",
                ["demo3-version-store/demo3c-ghost-records.sql"])
_config(S3C)
_add(S3C, "fk-safe-reset", "Back up ghost-demo rows and temporarily remove child FKs",
     "2", f"""
USE [{PRIMARY}];
DROP TABLE IF EXISTS #GhostItems;
DROP TABLE IF EXISTS #GhostOrders;
DROP TABLE IF EXISTS #GhostAccounts;
SELECT * INTO #GhostAccounts FROM dbo.Accounts WHERE AccountId BETWEEN 9901 AND 10000;
IF (SELECT COUNT(*) FROM #GhostAccounts) <> 100
    THROW 50000, 'Run demo0 to restore Accounts 9901 through 10000.', 1;
SELECT * INTO #GhostOrders FROM dbo.Orders WHERE AccountId BETWEEN 9901 AND 10000;
SELECT i.* INTO #GhostItems FROM dbo.OrderItems i
JOIN #GhostOrders o ON o.OrderId = i.OrderId;
BEGIN TRAN;
DELETE i FROM dbo.OrderItems i JOIN #GhostItems b ON b.ItemId = i.ItemId;
DELETE o FROM dbo.Orders o JOIN #GhostOrders b ON b.OrderId = o.OrderId;
COMMIT;
""", "Needed because the original setup randomly references these Accounts. "
     "Preserve session 2's temporary backups until exact restoration. This "
     "changes only the source DELETE range's dependencies; no schema invented. "
     "If interrupted, restore with approved demo0.", dangerous=True)


def _ghost_sql(table="Accounts"):
    return f"""
USE [{PRIMARY}];
SELECT OBJECT_NAME(object_id) AS TableName, index_id, ghost_record_count,
       version_ghost_record_count, record_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.{table}'),
                                   1, NULL, 'DETAILED')
WHERE index_level = 0;
"""


_add(S3C, "ghost-baseline", "Measure baseline ghost counts", "2",
     _ghost_sql(), "DETAILED physical stats are actual leaf-page observations; "
     "the scan may take time and itself acquire locks.")
_snapshot(S3C, query="SELECT TOP 1 AccountId FROM dbo.Accounts;")
_add(S3C, "delete", "Delete the original 100-account range", "2",
     f"USE [{PRIMARY}];\nDELETE FROM dbo.Accounts WHERE AccountId BETWEEN 9901 AND 10000;",
     "Autocommit DELETE on session 2; session 1's older snapshot remains "
     "open. FK dependencies were handled in the explicit prerequisite.", dangerous=True)
_add(S3C, "ghosts-held", "Measure ghost and version-ghost counts", "2",
     _ghost_sql(), "Separate ghost_record_count from version_ghost_record_count. "
     "Do not promise a fixed count or immediate physical removal: snapshot "
     "visibility can retain version ghosts.")
_tempdb(S3C, "versions-held")
_release(S3C)
_add(S3C, "ghosts-released", "Pause, then remeasure ghost cleanup", "2",
     _ghost_sql(), "Ghost cleanup and version cleanup are different mechanisms, "
     "but both must respect active readers; neither observation guarantees the "
     "other is complete. Pause manually, then inspect again.")
_tempdb(S3C, "versions-released")
_add(S3C, "restore-exact-seed", "Restore exact Accounts and FK identities", "2", f"""
USE [{PRIMARY}];
BEGIN TRAN;
SET IDENTITY_INSERT dbo.Accounts ON;
INSERT dbo.Accounts (AccountId, AccountName, Balance, Status, LastUpdated, Filler)
SELECT AccountId, AccountName, Balance, Status, LastUpdated, Filler FROM #GhostAccounts;
SET IDENTITY_INSERT dbo.Accounts OFF;
SET IDENTITY_INSERT dbo.Orders ON;
INSERT dbo.Orders (OrderId, AccountId, OrderDate, Amount)
SELECT OrderId, AccountId, OrderDate, Amount FROM #GhostOrders;
SET IDENTITY_INSERT dbo.Orders OFF;
SET IDENTITY_INSERT dbo.OrderItems ON;
INSERT dbo.OrderItems (ItemId, OrderId, ProductName, Quantity)
SELECT ItemId, OrderId, ProductName, Quantity FROM #GhostItems;
SET IDENTITY_INSERT dbo.OrderItems OFF;
COMMIT;
DROP TABLE #GhostItems;
DROP TABLE #GhostOrders;
DROP TABLE #GhostAccounts;
""", "Unlike the source's new-identity reseed, this preserves all original "
     "IDs, values and foreign keys so subsequent runs use the same DELETE "
     "range. Run once; on an interrupted restoration use approved demo0.",
     dangerous=True)
_cleanup(S3C)

S4A = _scenario("4a", "ADR: blocking, in-row diff, off-row promotion",
                "Beat 0 proves ADR alone does not enable versioned reads. "
                "After writer rollback AND End demo, enable RCSI/SNAPSHOT "
                "and inspect each of three committed updates.",
                ["demo4-adr-pvs/demo4a-adr-versioning-session1.sql",
                 "demo4-adr-pvs/demo4a-adr-versioning-session2.sql"])
_config(S4A, "adr-only", adr=True, rcsi=False, snapshot=False)
_reset(S4A)
_write_balance(S4A, "adr-only-writer", "200.00", begin=True)
_pvs_records(S4A, "adr-only-records")
# The held writer must not be used for monitoring; use an admin cross-database
# catalog view instead of creating a transaction on the reader connection.
S4A["steps"][-1]["session"] = "admin"
S4A["steps"][-1]["sql"] = S4A["steps"][-1]["sql"].replace(
    f"USE [{PRIMARY}];", "USE master;"
).replace("sys.dm_tran_persistent_version_store pvs",
          f"[{PRIMARY}].sys.dm_tran_persistent_version_store pvs").replace(
    "FROM sys.partitions", f"FROM [{PRIMARY}].sys.partitions").replace(
    "OBJECT_ID(N'dbo.Accounts')", f"OBJECT_ID(N'{PRIMARY}.dbo.Accounts')")
_page(S4A, "adr-only-page")
_read(S4A, "adr-only-blocked", "ADR without RCSI — start blocked read asynchronously",
      explanation="Start asynchronously on session 1. ADR generates recovery "
      "versions but READ COMMITTED still takes S locks. Next rollback the writer "
      "while the reader is waiting; never configure until it completes.")
_release(S4A, "adr-only-rollback", "2", rollback=True)
_read(S4A, "adr-only-after", "After rollback — original 100",
      explanation="Wait for the blocked read to finish. The writer's 200 was "
      "rolled back. NOW click End demo to close both connections before Beat 1.")
_config(S4A, "versioned-reads", adr=True)
_reset(S4A, key="beat1-reset")
_snapshot(S4A)
for number, value in enumerate(("200.00", "300.00", "400.00"), 1):
    _write_balance(S4A, f"update-{number}", value)
    _page(S4A, f"page-{number}")
    _pvs_records(S4A, f"records-{number}")
    _pvs(S4A, f"size-{number}")
_read(S4A, "held", "Snapshot before-image remains 100",
      explanation="Compare with original baseline; PVS rows and page tags "
      "prove storage independently of the frozen SQL balance. An in-row diff "
      "may be promoted off-row as later writers build history; actual layout "
      "depends on build, prior versions, diff size and page space.")
_release(S4A)
_read(S4A, "latest", "Outside snapshot — latest committed 400")
_pvs(S4A, "cleaner", "Pause, then measure background cleaner")
_tempdb(S4A, "locations", "Compare tempdb and active snapshot holders")
_cleanup(S4A)

S4B = _scenario("4b", "Wide update goes directly off-row", "Self-contained "
                "SavingsAccounts wide-column before-image; does not require "
                "4a. Reset ComplianceNotes before repeating so the wide "
                "UPDATE is actually a change.",
                ["demo4-adr-pvs/demo4b-adr-offrow-versioning-session1.sql",
                 "demo4-adr-pvs/demo4b-adr-offrow-versioning-session2.sql"])
_config(S4B, adr=True)
_reset(S4B, table="SavingsAccounts")
_add(S4B, "wide-reset", "Reset ComplianceNotes to its original default", "1", f"""
USE [{PRIMARY}];
UPDATE dbo.SavingsAccounts SET ComplianceNotes = DEFAULT WHERE AccountId = 42;
""", "Critical for repeatability: the next wide-column literal must differ "
     "from the old image, not be a no-op on a previous run.", dangerous=True)
_page(S4B, "baseline-page", "SavingsAccounts")
_snapshot(S4B, table="SavingsAccounts")
_add(S4B, "wide-update", "Commit the original wide-column UPDATE", "2",
     f"USE [{PRIMARY}];\n" + _statement(
         "demo4-adr-pvs/demo4b-adr-offrow-versioning-session2.sql",
         "UPDATE dbo.SavingsAccounts"),
     "Original Balance=999.99 and ComplianceNotes literal. Changing the wide "
     "column creates a larger before-image; inspect rather than assume placement.")
_page(S4B, "offrow-page", "SavingsAccounts")
_pvs_records(S4B, "offrow-records", "SavingsAccounts")
_pvs(S4B, "offrow-size")
_read(S4B, "held", "Snapshot Savings balance remains 100", table="SavingsAccounts")
_release(S4B)
_read(S4B, "latest", "Latest Savings balance (999.99)", table="SavingsAccounts")
_tempdb(S4B, "tempdb")
_force_cleanup(S4B, "cleanup-request")
_pvs(S4B, "after-cleanup")
_cleanup(S4B)

S4C = _scenario("4c", "PVS cleaner and instance-wide XTS",
                "Observe asynchronous cleanup, explicitly flush ADR cached "
                "pages with clean-session ADR OFF/ON transitions, then prove "
                "cross-database watermark pinning with two sessions.",
                ["demo4-adr-pvs/demo4c-pvs-cleaner-deep-dive.sql",
                 "demo4-adr-pvs/demo4c-session2.sql"])
_config(S4C, adr=True)
_pvs(S4C, "baseline")
_add(S4C, "generate", "Commit original 100K wide-row update", "2",
     f"USE [{PRIMARY}];\n" + _statement(
         "demo4-adr-pvs/demo4c-pvs-cleaner-deep-dive.sql", "UPDATE dbo.BigTable"),
     "A large committed UPDATE with no held snapshot. PVS may drain before "
     "inspection. The intended 100K updates are not measured version records.",
     dangerous=True)
_pvs(S4C, "after-update")
_pvs(S4C, "background", "Pause, then remeasure background cleanup")
_config(S4C, "flush-adr-off", adr=False)
_pvs(S4C, "flushed", "Observe residual records after ADR OFF")
_config(S4C, "restore-adr-on", adr=True)
_config(S4C, "configure-eagles", db=EAGLES, adr=True)
_snapshot(S4C, query="SELECT TOP 1 Id FROM dbo.BigTable;")
_add(S4C, "other-db-update", "Commit original ReportData update in eaglesdontfly",
     "2", f"USE [{EAGLES}];\n" + _statement(
         "demo4-adr-pvs/demo4c-session2.sql", "UPDATE dbo.ReportData"),
     "Session 1 read BigTable in the primary database, but version writes occur "
     "in another database. ReportData's source workload is substantial.",
     dangerous=True)
_pvs(S4C, "other-db-size", db=EAGLES)
_skips(S4C, "skips-before", EAGLES)
_force_cleanup(S4C, "pinned-cleanup", EAGLES)
_pvs(S4C, "still-pinned", db=EAGLES)
_skips(S4C, "skips-after", EAGLES)
_add(S4C, "xts-floors", "Compare instance-wide XTS floors", "admin", f"""
USE master;
SELECT DB_NAME(database_id) AS [Database], min_transaction_timestamp AS XTS_Floor,
       persistent_version_store_size_kb AS PVS_Size_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id IN (DB_ID(N'{PRIMARY}'), DB_ID(N'{EAGLES}'));
{ACTIVE}
""", "Compare actual XTS timestamps and the primary-database reader against "
     "eaglesdontfly's retained versions. PVS storage is per database; do not "
     "infer that cleanup timestamps are isolated per database.")
_release(S4C)
_force_cleanup(S4C, "released-cleanup", EAGLES)
_pvs(S4C, "drained", "Pause, then observe released eagles PVS", EAGLES)
_config(S4C, "restore-eagles-adr-off", db=EAGLES, adr=False)
_cleanup(S4C)

S4D = _scenario("4d", "Cross-table watermark pinning",
                "Hold a BigTable snapshot on session 1; all committed writers "
                "run on session 2 (not inside the reader transaction). Measure "
                "Accounts and BigTable versions, skip reasons, idle holders, "
                "then release and drain. Source's per-database isolation "
                "claim is not a measured fact; compare 4c.",
                ["demo4-adr-pvs/demo4d-pvs-watermark-pinning.sql"])
_config(S4D, adr=True)
_reset(S4D)
_pvs(S4D, "baseline")
_snapshot(S4D, query="SELECT TOP 1 Id FROM dbo.BigTable;")
for key, beginning in (
    ("batch-a", "UPDATE dbo.BigTable SET Val = Val + 1, Payload = 'Watermark test batch A."),
    ("batch-b", "UPDATE dbo.BigTable SET Val = Val + 1, Payload = 'Watermark test batch B."),
    ("accounts", "UPDATE dbo.Accounts SET Balance = Balance + 0.01"),
):
    _add(S4D, key, "Commit " + key + " while BigTable snapshot is held", "2",
         f"USE [{PRIMARY}];\n" + _statement(
             "demo4-adr-pvs/demo4d-pvs-watermark-pinning.sql", beginning),
         "Original source DML, deliberately assigned to the other autocommit "
         "connection. The snapshot read only BigTable, but Accounts versions "
         "can also be retained by its timestamp.", dangerous=True)
_read(S4D, "sample-current", "Committed Accounts sample (100.01)", "2")
_pvs(S4D, "held-by-table")
_skips(S4D, "before-skips")
_force_cleanup(S4D, "try-pinned")
_skips(S4D, "after-skips")
_pvs(S4D, "pinned")
_release(S4D)
_force_cleanup(S4D, "try-released")
_pvs(S4D, "drain", "Pause, then measure released PVS")
_add(S4D, "restore-accounts", "Undo Accounts increment and restore filler", "2",
     f"USE [{PRIMARY}];\n" + _statement(
         "demo4-adr-pvs/demo4d-pvs-watermark-pinning.sql",
         "UPDATE dbo.Accounts SET Balance = Balance - 0.01"),
     "Original paired reset. Run exactly once after the Accounts wave "
     "succeeded. It removes this demo's 0.01 drift; BigTable workload mutations "
     "remain unless you run approved demo0.", dangerous=True)
_read(S4D, "sample-restored", "Restored Accounts sample (100)", "2")
_cleanup(S4D)

S4E = _scenario("4e", "Traditional versus ADR rollback and recovery",
                "MANUAL LARGE WORKLOAD: use only a disposable approved lab "
                "with enough log/data/tempdb space. No automatic server restart, "
                "KILL, crash or recovery is performed. Finish a rollback and "
                "End demo before changing ADR. Timing SELECTs are measurements, "
                "not promises of instant recovery.",
                ["demo4-adr-pvs/demo4e-adr-recovery.sql"])
_config(S4E, "traditional-config", adr=False)
_tempdb(S4E, "traditional-baseline")
for mode in ("traditional", "adr"):
    if mode == "adr":
        _config(S4E, "adr-config", adr=True)
    _add(S4E, f"{mode}-large-update", f"MANUAL — {mode} 500K-row UPDATE", "2", f"""
USE [{PRIMARY}];
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRAN;
UPDATE dbo.BigTable SET Val = Val + 1;
SELECT @@ROWCOUNT AS ActualUpdatedRows;
""", "Dangerous manual large workload from the original source. May run for "
         "a long time and generate substantial log/versions. Do not configure "
         "or End demo mid-workload if you want comparable timed rollback; "
         "wait for completion, then select the next rollback step.",
         dangerous=True)
    _add(S4E, f"{mode}-timed-rollback", f"MANUAL — measure {mode} rollback", "2", f"""
DECLARE @rollback_start datetime2 = SYSUTCDATETIME();
IF @@TRANCOUNT > 0 ROLLBACK;
SELECT N'{mode} rollback elapsed on this run' AS Observation,
       DATEDIFF(MILLISECOND, @rollback_start, SYSUTCDATETIME()) AS RollbackMilliseconds;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
""", "Measures only the synchronous ROLLBACK call, not async cleanup, the "
         "preceding UPDATE or crash recovery. Run immediately after the matching "
         "UPDATE completes. Before the ADR configuration, click End demo.",
         dangerous=True)
_pvs(S4E, "rollback-pvs")
_tempdb(S4E, "rollback-tempdb")
_snapshot(S4E, query="SELECT TOP 1 Id FROM dbo.BigTable;")
for key, where in (("wave-a", "Id <= 100000"), ("wave-b", "Id BETWEEN 100001 AND 200000")):
    _add(S4E, key, "MANUAL — committed " + key, "2",
         f"USE [{PRIMARY}];\nUPDATE dbo.BigTable SET Val = Val + 1 WHERE {where};",
         "Original companion-session workload; committed independently of the "
         "snapshot reader.", dangerous=True)
_pvs(S4E, "held")
_tempdb(S4E, "holders")
_release(S4E)
_force_cleanup(S4E, "release-cleanup")
_pvs(S4E, "release-size")
_add(S4E, "ghost-baseline", "Measure BigTable ghost counts before DELETE", "2",
     _ghost_sql("BigTable"), "Original ADR ghost-versus-PVS extension.")
_add(S4E, "backup-deletes", "Back up the original 1000-row DELETE range", "2", f"""
USE [{PRIMARY}];
DROP TABLE IF EXISTS #RecoveryDeleted;
SELECT * INTO #RecoveryDeleted FROM dbo.BigTable WHERE Id BETWEEN 1 AND 1000;
IF (SELECT COUNT(*) FROM #RecoveryDeleted) <> 1000
    THROW 50000, 'Run demo0 to restore BigTable IDs 1 through 1000.', 1;
""", "Keep this session alive until restoration. Original new-identity "
     "reseed would make repeated deletes target no rows.", dangerous=True)
_snapshot(S4E, "ghost-snapshot", query="SELECT TOP 1 Id FROM dbo.BigTable;")
_add(S4E, "ghost-delete", "MANUAL — delete BigTable IDs 1–1000", "2",
     f"USE [{PRIMARY}];\nDELETE FROM dbo.BigTable WHERE Id BETWEEN 1 AND 1000;",
     "Session 2 autocommit; older session 1 snapshot retains before-images.",
     dangerous=True)
_add(S4E, "ghost-held", "Measure retained ghosts", "2", _ghost_sql("BigTable"),
     "Separate ghosts/version ghosts from off-row PVS measurements.")
_pvs(S4E, "ghost-pvs")
_tempdb(S4E, "ghost-tempdb")
_release(S4E, "ghost-release")
_force_cleanup(S4E, "ghost-cleanup")
_add(S4E, "ghost-after", "Pause, then measure ghost cleanup", "2",
     _ghost_sql("BigTable"), "Timer-driven cleanup may not yet be complete.")
_pvs(S4E, "ghost-drain")
_add(S4E, "restore-deletes", "Restore exact BigTable IDs and values", "2", f"""
USE [{PRIMARY}];
SET IDENTITY_INSERT dbo.BigTable ON;
INSERT dbo.BigTable (Id, Val, Payload) SELECT Id, Val, Payload FROM #RecoveryDeleted;
SET IDENTITY_INSERT dbo.BigTable OFF;
DROP TABLE #RecoveryDeleted;
""", "Restores the deleted range exactly for repeatability, rather than the "
     "source's random new-identity reseed. Prior committed workload increments "
     "remain; approved demo0 restores a completely fresh lab.", dangerous=True)
_add(S4E, "recovery-log", "Read existing recovery log evidence (no crash)", "admin",
     f"USE master;\nEXEC sys.xp_readerrorlog 0, 1, N'{PRIMARY}', N'Recovery';",
     "Original optional error-log query. Only existing recovery messages are "
     "read; an empty result is valid. The commented kill/restart experiment "
     "is intentionally not executable in this web catalog.")
_cleanup(S4E)


DEMOS = [
    dict(id="0", title="Setup", folder=DEMO_FOLDERS["0"], description="Approved destructive setup and read-only readiness.",
         scenarios=[S0]),
    dict(id="1", title="Blocking", folder=DEMO_FOLDERS["1"], description="Blocking and the dirty-read trap.",
         scenarios=[S1]),
    dict(id="2", title="RCSI & Snapshot", folder=DEMO_FOLDERS["2"], description="Consistency, update conflicts and FK surprises.",
         scenarios=[S2A, S2B, S2C, S2D, S2E]),
    dict(id="3", title="Version Store Internals", nav_title="Version Store", folder=DEMO_FOLDERS["3"], description="Pages, chains, global pinning and ghosts.",
         scenarios=[S3A, S3B, S3C]),
    dict(id="4", title="ADR & PVS", folder=DEMO_FOLDERS["4"], description="Version placement, cleaner watermarks and rollback.",
         scenarios=[S4A, S4B, S4C, S4D, S4E]),
]
