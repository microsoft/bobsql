"""Explicit reversals of the known demo SQL, not database backups or snapshots."""

import re

from catalog import COWBOYS, DEMOS, EAGLES, PRIMARY


SCENARIOS = {s["id"]: s for d in DEMOS if d["id"] != "0" for s in d["scenarios"]}


def databases(scenario_id: str) -> list[str]:
    if scenario_id == "3b":
        return [EAGLES, COWBOYS]
    return [PRIMARY, EAGLES] if scenario_id == "4c" else [PRIMARY]


def configuration(scenario_id: str) -> str:
    statements = ["USE master;"]
    for db in databases(scenario_id):
        adr = db == PRIMARY and scenario_id in ("4a", "4b", "4c", "4d")
        rcsi = scenario_id not in ("1", "2c", "4a")
        snapshot = scenario_id not in ("1", "4a", "4b")
        statements.extend([
            f"ALTER DATABASE [{db}] SET OPTIMIZED_LOCKING = OFF;",
            f"ALTER DATABASE [{db}] SET ACCELERATED_DATABASE_RECOVERY = {'ON' if adr else 'OFF'};",
            f"ALTER DATABASE [{db}] SET READ_COMMITTED_SNAPSHOT {'ON' if rcsi else 'OFF'};",
            f"ALTER DATABASE [{db}] SET ALLOW_SNAPSHOT_ISOLATION {'ON' if snapshot else 'OFF'};",
            f"ALTER DATABASE [{db}] SET MULTI_USER;",
            f"IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'{db}' "
            f"AND is_optimized_locking_on = 0 AND is_accelerated_database_recovery_on = {int(adr)} "
            f"AND is_read_committed_snapshot_on = {int(rcsi)} AND snapshot_isolation_state = {int(snapshot)} "
            "AND user_access_desc = N'MULTI_USER') "
            "THROW 50000, 'Database options have not returned to their starting state. Retry Reset demo.', 1;",
        ])
    return "\n".join(statements)


def restoration_session(scenario_id: str, jobs: list[dict]) -> str | None:
    pairs = {
        "2d": ("insert", "remove-insert", "1"),
        "2e": ("fk-reset", "restore-items", "2"),
        "3c": ("fk-safe-reset", "restore-exact-seed", "2"),
        "4e": ("backup-deletes", "restore-deletes", "2"),
    }
    if scenario_id not in pairs:
        return None
    before, after, session = pairs[scenario_id]
    pending = False
    for job in jobs:
        if job["status"] == "succeeded":
            if job["step_id"] == f"{scenario_id}-{before}":
                pending = True
            elif job["step_id"] == f"{scenario_id}-{after}":
                pending = False
    return session if pending else None


def check_restoration_order(scenario_id: str, jobs: list[dict]) -> None:
    required = {
        "2e": {"unrelated-update", "indexed-unrelated-update"},
        "3c": {"delete"},
        "4e": {"ghost-delete"},
    }.get(scenario_id, set())
    prefix = []
    for job in jobs:
        if (job["status"] == "succeeded" and
                job["step_id"].removeprefix(f"{scenario_id}-") in required and
                restoration_session(scenario_id, prefix) is None):
            raise ValueError("A destructive step ran without its original restoration tables. "
                             "Reset cannot recover those rows safely; use approved setup.")
        if (scenario_id == "4e" and job["status"] == "succeeded" and
                job["step_id"] in ("4e-wave-a", "4e-wave-b") and
                restoration_session(scenario_id, prefix) is not None):
            raise ValueError("An update wave ran while deleted-row restoration was pending. "
                             "Reset cannot infer every row's original value safely.")
        prefix.append(job)


def data_sql(scenario_id: str, jobs: list[dict]) -> str:
    scenario = SCENARIOS[scenario_id]
    steps = {step["id"]: step for step in scenario["steps"]}
    if not jobs and scenario_id in ("2d", "2e", "3b", "3c", "4c", "4d", "4e"):
        raise ValueError("This reset needs this app's execution history to undo committed changes "
                         "safely. No run is recorded (the app may have restarted). "
                         "Use the existing restoration steps or approved Demo 0; no reset was performed.")
    check_restoration_order(scenario_id, jobs)
    for job in jobs:
        step = steps.get(job["step_id"], {})
        if (job["status"] in ("failed", "cancelled") and
                not step.get("expected_error") and
                not job["step_id"].endswith(("-large-update", "-timed-rollback")) and
                (re.search(r"\b(?:UPDATE|INSERT|DELETE)\b", step.get("sql", ""), re.I)
                 or (scenario_id == "3b" and re.fullmatch(r"3b-wave-(?:[1-9]|10)", job["step_id"]))) and
                scenario_id in ("2d", "2e", "3b", "3c", "4c", "4d", "4e")):
            raise ValueError("A data-changing step failed or was cancelled. Its committed effect "
                             "cannot be inferred safely; reset stopped instead of guessing.")
    def count(key):
        return sum(j["status"] == "succeeded" and j["step_id"] == f"{scenario_id}-{key}"
                   for j in jobs)
    sql = [f"USE [{PRIMARY}];"]
    account = {
        "1": ("1", "100.00"), "2a": ("1", "100.00"),
        "2b": ("200", "1000.00"), "2c": ("100", "100.00"),
        "2d": ("1", "100.00"), "3a": ("42", "100.00"),
        "4a": ("42", "100.00"),
    }
    if scenario_id in account:
        ids, value = account[scenario_id]
        sql.extend([
            f"UPDATE dbo.Accounts SET Balance = {value}, LastUpdated = DEFAULT WHERE AccountId IN ({ids});",
            f"IF @@ROWCOUNT <> {len(ids.split(','))} THROW 50000, 'Required Accounts rows are missing. Run approved setup.', 1;",
        ])
    owner = restoration_session(scenario_id, jobs)
    if owner:
        restore_key = {
            "2d": "remove-insert", "2e": "restore-items",
            "3c": "restore-exact-seed", "4e": "restore-deletes",
        }[scenario_id]
        restore = steps[f"{scenario_id}-{restore_key}"]["sql"]
        restore = re.sub(r"(?m)^\s*(?:BEGIN TRAN;|COMMIT;|DROP TABLE #[^;]+;)\s*$", "", restore)
        if scenario_id == "3c":
            for table, key, temp in (("Accounts", "AccountId", "#GhostAccounts"),
                                     ("Orders", "OrderId", "#GhostOrders"),
                                     ("OrderItems", "ItemId", "#GhostItems")):
                restore = restore.replace(
                    f"FROM {temp};",
                    f"FROM {temp} b WHERE NOT EXISTS "
                    f"(SELECT 1 FROM dbo.{table} t WHERE t.{key} = b.{key});",
                )
        elif scenario_id == "4e":
            restore = restore.replace(
                "FROM #RecoveryDeleted;",
                "FROM #RecoveryDeleted b WHERE NOT EXISTS "
                "(SELECT 1 FROM dbo.BigTable t WHERE t.Id = b.Id);",
            )
        sql.append(restore)
    if scenario_id == "2e":
        sql.append("DROP INDEX IF EXISTS IX_OrderItems_OrderId ON dbo.OrderItems;")
    if scenario_id == "3b":
        waves = (10 * count("waves") + sum(count(f"wave-{n}") for n in range(1, 11))
                 - 10 * count("restore-yards"))
        sql.append(f"USE [{COWBOYS}]; UPDATE dbo.GameStats SET Yards = Yards - ({waves});")
    if scenario_id == "4b":
        sql.extend([
            "UPDATE dbo.SavingsAccounts SET Balance = 100.00, LastUpdated = DEFAULT, "
            "ComplianceNotes = DEFAULT WHERE AccountId = 42;",
            "IF @@ROWCOUNT <> 1 THROW 50000, 'SavingsAccounts 42 is missing. Run approved setup.', 1;",
        ])
    if scenario_id == "4c":
        if count("generate"):
            sql.append(f"UPDATE dbo.BigTable SET Val = Val - ({count('generate')}), Payload = DEFAULT WHERE Id <= 100000;")
        if count("other-db-update"):
            sql.append(f"USE [{EAGLES}]; UPDATE dbo.ReportData SET Score = Score - ({count('other-db-update')}), Notes = DEFAULT;")
    if scenario_id == "4d":
        if count("batch-a"):
            sql.append(f"UPDATE dbo.BigTable SET Val = Val - ({count('batch-a')}), Payload = DEFAULT WHERE Id <= 50000;")
        if count("batch-b"):
            sql.append(f"UPDATE dbo.BigTable SET Val = Val - ({count('batch-b')}), Payload = DEFAULT WHERE Id BETWEEN 50001 AND 100000;")
        if count("accounts") or count("restore-accounts"):
            sql.append(f"UPDATE dbo.Accounts SET Balance = Balance - (0.01 * ({count('accounts') - count('restore-accounts')})), Filler = DEFAULT;")
        sql.append("UPDATE dbo.Accounts SET Balance = 100.00, LastUpdated = DEFAULT WHERE AccountId = 42;")
    if scenario_id == "4e":
        sql.extend([
            f"UPDATE dbo.BigTable SET Val = Val - ({count('wave-a')}) WHERE Id <= 100000;",
            f"UPDATE dbo.BigTable SET Val = Val - ({count('wave-b')}) WHERE Id BETWEEN 100001 AND 200000;",
        ])
    cleanup = ("SET IDENTITY_INSERT dbo.Accounts OFF; SET IDENTITY_INSERT dbo.Orders OFF; "
               "SET IDENTITY_INSERT dbo.OrderItems OFF;") if scenario_id == "3c" else (
               "SET IDENTITY_INSERT dbo.BigTable OFF;" if scenario_id == "4e" else "")
    return ("SET XACT_ABORT ON;\nBEGIN TRY\nBEGIN TRAN;\n" + "\n".join(sql) +
            "\nCOMMIT;\nEND TRY\nBEGIN CATCH\nIF @@TRANCOUNT > 0 ROLLBACK;\n" +
            cleanup + "\nTHROW;\nEND CATCH;\nUSE master;")
