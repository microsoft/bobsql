import unittest
from unittest.mock import Mock, patch

from app import DemoRunner, SqlError, create_app
from reset_demo import SCENARIOS, configuration, data_sql, restoration_session


def job(scenario, key, status="succeeded"):
    return {"scenario_id": scenario, "step_id": f"{scenario}-{key}", "status": status}


class ResetSqlTests(unittest.TestCase):
    def test_every_walkthrough_has_explicit_reset_sql(self):
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                sql = data_sql(scenario, [job(scenario, SCENARIOS[scenario]["steps"][0]["id"].split("-", 1)[1])])
                self.assertIn("BEGIN TRAN;", sql)
                self.assertIn("ROLLBACK;", sql)
                self.assertIn("THROW;", sql)
                combined = sql + configuration(scenario)
                for forbidden in ("BACKUP DATABASE", "RESTORE DATABASE", "CREATE DATABASE", "DROP DATABASE", "SELECT * INTO"):
                    self.assertNotIn(forbidden, combined)
                self.assertNotIn("ROLLBACK IMMEDIATE", configuration(scenario))
                self.assertIn("snapshot_isolation_state", configuration(scenario))

    def test_fixed_starting_balances(self):
        for scenario, predicate, value in (("1", "1", "100.00"), ("2a", "1", "100.00"),
                                            ("2b", "200", "1000.00"), ("2c", "100", "100.00"),
                                            ("3a", "42", "100.00"), ("4a", "42", "100.00")):
            sql = data_sql(scenario, [])
            self.assertIn(f"Balance = {value}", sql)
            self.assertIn(f"AccountId IN ({predicate})", sql)
            self.assertIn("IF @@ROWCOUNT <>", sql)
        self.assertIn("ComplianceNotes = DEFAULT", data_sql("4b", []))
        self.assertIn("READ_COMMITTED_SNAPSHOT ON", configuration("4b"))
        self.assertIn("ALLOW_SNAPSHOT_ISOLATION OFF", configuration("4b"))

    def test_partial_waves_and_intentional_repeats_are_counted(self):
        jobs = [job("3b", "configure-culprit"), job("3b", "wave-1"),
                job("3b", "wave-2"), job("3b", "wave-2")]
        self.assertIn("Yards = Yards - (3)", data_sql("3b", jobs))
        jobs.append(job("3b", "restore-yards"))
        self.assertIn("Yards = Yards - (-7)", data_sql("3b", jobs))

    def test_combined_waves_and_repeats_compensate_ten_commits_each(self):
        jobs = [job("3b", "configure-culprit"), job("3b", "waves")]
        self.assertIn("Yards = Yards - (10)", data_sql("3b", jobs))
        jobs.append(job("3b", "waves"))
        self.assertIn("Yards = Yards - (20)", data_sql("3b", jobs))
        jobs.append(job("3b", "restore-yards"))
        self.assertIn("Yards = Yards - (10)", data_sql("3b", jobs))
        for status in ("failed", "cancelled"):
            with self.assertRaisesRegex(ValueError, "cannot be inferred"):
                data_sql("3b", [job("3b", "waves", status)])

    def test_missing_history_and_uncertain_commits_stop(self):
        for scenario in ("2d", "2e", "3b", "3c", "4c", "4d", "4e"):
            with self.subTest(scenario=scenario):
                with self.assertRaisesRegex(ValueError, "history"):
                    data_sql(scenario, [])
        for status in ("failed", "cancelled"):
            with self.assertRaisesRegex(ValueError, "cannot be inferred"):
                data_sql("3b", [job("3b", "wave-1", status)])
        self.assertIn("Val = Val - (0)", data_sql("4e", [job("4e", "traditional-large-update", "cancelled")]))

    def test_fk_restore_uses_existing_session_and_is_not_repeated_after_cleanup(self):
        jobs = [job("2e", "fk-reset")]
        self.assertEqual(restoration_session("2e", jobs), "2")
        self.assertIn("JOIN #FkOriginalItems", data_sql("2e", jobs))
        self.assertNotIn("DROP TABLE #FkOriginalItems", data_sql("2e", jobs))
        jobs.append(job("2e", "restore-items"))
        self.assertIsNone(restoration_session("2e", jobs))
        self.assertNotIn("JOIN #FkOriginalItems", data_sql("2e", jobs))
        self.assertIn("DROP INDEX IF EXISTS IX_OrderItems_OrderId", data_sql("2e", jobs))

    def test_ghost_restore_works_before_or_after_delete(self):
        sql = data_sql("3c", [job("3c", "fk-safe-reset")])
        for name in ("#GhostAccounts", "#GhostOrders", "#GhostItems"):
            self.assertIn(f"FROM {name} b WHERE NOT EXISTS", sql)
            self.assertNotIn(f"DROP TABLE {name}", sql)
        self.assertLess(sql.index("INSERT dbo.Accounts"), sql.index("INSERT dbo.Orders"))
        self.assertLess(sql.index("INSERT dbo.Orders"), sql.index("INSERT dbo.OrderItems"))

    def test_missing_preparation_or_wave_during_deleted_range_stops(self):
        for scenario, key in (("2e", "unrelated-update"), ("3c", "delete"), ("4e", "ghost-delete")):
            with self.assertRaisesRegex(ValueError, "without its original restoration"):
                data_sql(scenario, [job(scenario, key)])
        with self.assertRaisesRegex(ValueError, "while deleted-row restoration"):
            data_sql("4e", [job("4e", "backup-deletes"), job("4e", "ghost-delete"), job("4e", "wave-a")])

    def test_recovery_restore_precedes_wave_reversal(self):
        jobs = [job("4e", "wave-a"), job("4e", "wave-a"), job("4e", "wave-b"),
                job("4e", "backup-deletes")]
        sql = data_sql("4e", jobs)
        self.assertIn("FROM #RecoveryDeleted b WHERE NOT EXISTS", sql)
        self.assertLess(sql.index("INSERT dbo.BigTable"), sql.index("Val = Val - (2)"))
        self.assertIn("Val = Val - (1) WHERE Id BETWEEN 100001 AND 200000", sql)

    def test_cross_database_and_cross_table_compensation(self):
        sql = data_sql("4c", [job("4c", "generate"), job("4c", "generate"),
                              job("4c", "other-db-update")])
        self.assertIn("Val = Val - (2), Payload = DEFAULT", sql)
        self.assertIn("USE [eaglesdontfly]; UPDATE dbo.ReportData SET Score = Score - (1), Notes = DEFAULT", sql)
        sql = data_sql("4d", [job("4d", "batch-a"), job("4d", "accounts"),
                              job("4d", "restore-accounts")])
        self.assertIn("0.01 * (0)", sql)
        self.assertNotIn("WHERE Id BETWEEN 50001 AND 100000", sql)

    def test_configuration_restores_scenario_start_not_arbitrary_prior_options(self):
        self.assertIn("ALLOW_SNAPSHOT_ISOLATION OFF", configuration("1"))
        self.assertIn("READ_COMMITTED_SNAPSHOT OFF", configuration("4a"))
        self.assertIn("ACCELERATED_DATABASE_RECOVERY = ON", configuration("4a"))
        self.assertIn("ACCELERATED_DATABASE_RECOVERY = OFF", configuration("4e"))


class ResetRunnerTests(unittest.TestCase):
    def test_idle_sessions_return_to_master_before_pooling(self):
        runner = DemoRunner()
        connection = Mock()
        session = {"name": "2", "busy": False, "cancel_requested": False,
                   "connection": connection}
        runner.sessions = {"2": session}
        events = []
        connection.close.side_effect = lambda: events.append("close")
        with patch("app.execute_sql", side_effect=lambda conn, sql: events.append(sql)):
            runner._close_sessions([session])
        self.assertIn("ROLLBACK;", events[0])
        self.assertIn("USE master;", events[0])
        self.assertEqual(events[1], "close")
        self.assertEqual(runner.sessions, {})

    def test_api_requires_boolean_confirmation_and_selected_scenario(self):
        runner = Mock()
        client = create_app(runner).test_client()
        for body in ({}, [], {"confirmed": "true", "scenario_id": "1"},
                     {"confirmed": True, "scenario_id": 1}):
            self.assertEqual(client.post("/api/restart", json=body).status_code, 400)
        runner.restart.assert_not_called()
        self.assertEqual(client.post("/api/restart", json={"confirmed": True, "scenario_id": "1"}).status_code, 200)
        runner.restart.assert_called_once_with("1")

    def test_wrong_demo_and_wrong_walkthrough_do_not_touch_sql(self):
        runner = DemoRunner()
        runner.active_demo = "2"
        with patch("app.execute_sql") as sql:
            with self.assertRaisesRegex(ValueError, "different demo"):
                runner.restart("1")
            runner.active_demo = None
            runner.jobs = [job("2a", "configure")]
            with self.assertRaisesRegex(ValueError, "Another walkthrough"):
                runner.restart("1")
            sql.assert_not_called()

    def test_missing_or_busy_restoration_session_is_preserved(self):
        runner = DemoRunner()
        runner.jobs = [job("3c", "fk-safe-reset")]
        with patch("app.execute_sql") as sql:
            for sessions in ({}, {"2": {"busy": True}}):
                runner.sessions = sessions
                with self.assertRaisesRegex(ValueError, "restoration tables"):
                    runner.restart("3c")
            sql.assert_not_called()

    def test_repeating_preparation_cannot_destroy_original_restoration_rows(self):
        runner = DemoRunner()
        runner.jobs = [job("3c", "fk-safe-reset")]
        runner.active_demo = "3"
        with self.assertRaisesRegex(ValueError, "must not be overwritten"):
            runner.run("3c-fk-safe-reset", True)

    def test_success_archives_progress_but_retains_history(self):
        runner = DemoRunner()
        runner.jobs = [job("1", "configure"), job("1", "dirty-writer")]
        connection = Mock()
        with patch.object(runner, "connection", return_value=connection), patch("app.execute_sql", return_value=([{"rows": []}], [])) as sql:
            runner.restart("1")
        self.assertEqual(len(runner.jobs), 2)
        self.assertTrue(all(j["archived"] for j in runner.jobs))
        self.assertFalse(runner.resetting)
        self.assertEqual(runner.restart_data_done, set())
        self.assertTrue(any("Balance = 100.00" in call.args[1] for call in sql.call_args_list))

    def test_settings_failure_retry_does_not_reverse_data_twice(self):
        runner = DemoRunner()
        runner.jobs = [job("3b", "wave-1")]
        connection = Mock()
        with patch.object(runner, "connection", return_value=connection):
            def execute(_connection, sql):
                if "ALTER DATABASE" in sql:
                    raise SqlError("Configuration failed", "")
                return [{"rows": []}], []
            with patch("app.execute_sql", side_effect=execute):
                with self.assertRaises(SqlError):
                    runner.restart("3b")
            self.assertIn("3b", runner.restart_data_done)
            self.assertFalse(runner.jobs[0].get("archived", False))
            with patch("app.execute_sql", return_value=([{"rows": []}], [])) as sql:
                runner.restart("3b")
            self.assertFalse(any("UPDATE dbo.GameStats" in c.args[1] for c in sql.call_args_list))
            self.assertEqual(runner.restart_data_done, set())

    def test_restoration_happens_before_session_close(self):
        runner = DemoRunner()
        runner.jobs = [job("2e", "fk-reset")]
        owner = Mock()
        session = {"name": "2", "busy": False, "cancel_requested": False, "connection": owner}
        runner.sessions = {"2": session}
        events = []
        owner.close.side_effect = lambda: events.append("close")
        def execute(connection, sql):
            if "JOIN #FkOriginalItems" in sql:
                self.assertIs(connection, owner)
                events.append("restore")
            return [{"rows": []}], []
        with patch.object(runner, "connection", return_value=Mock()), patch("app.execute_sql", side_effect=execute):
            runner.restart("2e")
        self.assertEqual(events, ["restore", "close"])

    def test_restoration_error_retains_owner_and_progress(self):
        runner = DemoRunner()
        runner.jobs = [job("2e", "fk-reset")]
        owner = Mock()
        session = {"name": "2", "busy": False, "cancel_requested": False, "connection": owner}
        runner.sessions = {"2": session}
        with patch("app.execute_sql", side_effect=SqlError("Missing temp table", "")):
            with self.assertRaises(SqlError):
                runner.restart("2e")
        owner.close.assert_not_called()
        self.assertIs(runner.sessions["2"], session)
        self.assertFalse(runner.jobs[0].get("archived", False))
        self.assertFalse(runner.resetting)

    def test_both_guards_exclude_owned_connections_and_report_external_clients(self):
        runner = DemoRunner()
        runner.jobs = [job("1", "configure")]
        calls = []

        def execute(_connection, sql):
            if "SELECT s.session_id, s.program_name" in sql:
                calls.append(sql)
                self.assertIn(f"s.context_info <> 0x{runner.context_hex}", sql)
                self.assertIn("sys.dm_tran_locks", sql)
                return [{"rows": [] if len(calls) == 1 else [
                    [77, "Microsoft SQL Server Management Studio", "starswillwinthecup"]
                ]}], []
            return [], []

        with patch.object(runner, "connection", return_value=Mock()), patch("app.execute_sql", side_effect=execute):
            with self.assertRaisesRegex(ValueError, "SPID 77.*Management Studio"):
                runner.restart("1")
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0], calls[1])
        self.assertIn("1", runner.restart_data_done)
        self.assertFalse(runner.jobs[0].get("archived", False))
        self.assertFalse(runner.resetting)

    def test_outside_connection_stops_before_data_or_session_changes(self):
        runner = DemoRunner()
        runner.jobs = [job("1", "configure")]
        session = {"busy": False, "cancel_requested": False, "connection": Mock()}
        runner.sessions = {"1": session}
        with patch.object(runner, "connection", return_value=Mock()), patch(
            "app.execute_sql", return_value=([{"rows": [[88, "SQL client", "starswillwinthecup"]]}], [])
        ) as sql:
            with self.assertRaisesRegex(ValueError, "SPID 88"):
                runner.restart("1")
        self.assertEqual(sql.call_count, 1)
        session["connection"].close.assert_not_called()
        self.assertEqual(runner.restart_data_done, set())


if __name__ == "__main__":
    unittest.main()
