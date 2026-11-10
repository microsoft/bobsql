import threading
import unittest
from unittest.mock import Mock, patch

from app import DATABASES, DemoRunner, GO, SqlError, create_app, execute_sql
from catalog import COWBOYS, EAGLES, PRIMARY, _balance


class CursorStub:
    def __init__(self):
        self.description = [("value",)]
        self.messages = []
        self.batches = []
        self.remaining = False

    def execute(self, sql):
        self.batches.append(sql.strip())
        self.remaining = True

    def fetchmany(self, _size):
        if self.remaining:
            self.remaining = False
            return [(42,)]
        return []

    def nextset(self):
        return False

    def close(self):
        pass


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.runner = Mock()
        self.runner.server = "localhost"
        self.client = create_app(self.runner).test_client()

    def test_rejects_cross_origin_execution(self):
        result = self.client.post("/api/run", json={"step_id": "x"},
                                  headers={"Origin": "https://example.com"})
        self.assertEqual(result.status_code, 403)
        self.runner.run.assert_not_called()

    def test_page_viewers_open_prefilled_without_sql(self):
        viewers = self.client.application.config["PAGE_VIEWERS"]
        for kind, table, database in (
            ("tempdb", "Accounts", PRIMARY),
            ("tempdb", "GameStats", COWBOYS),
            ("adr", "SavingsAccounts", PRIMARY),
        ):
            with self.subTest(kind=kind, table=table), patch.object(viewers[kind], "get_connection") as connect:
                response = self.client.get(f"/page-viewer/{kind}", query_string={
                    "database": database, "table_name": table, "find_row": "1",
                })
                self.assertEqual(response.status_code, 200)
                html = response.get_data(as_text=True)
                self.assertIn(f'value="{database}"', html)
                self.assertIn(f'value="{table}" selected', html)
                self.assertIn('name="find_row" value="1"', html)
                self.assertIn("View Page", html)
                connect.assert_not_called()
        self.assertEqual(self.runner.mock_calls, [])
        self.assertEqual(self.client.get("/page-viewer/missing").status_code, 404)

    def test_page_viewer_form_rejects_cross_origin_execution(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["tempdb"]
        with patch.object(viewer, "get_connection") as connect:
            response = self.client.post("/page-viewer/tempdb", data={"find_row": "42"},
                                        headers={"Origin": "https://example.com"})
            self.assertEqual(response.status_code, 403)
            connect.assert_not_called()

    def test_page_viewers_reuse_formatters_and_close_diagnostic_connections(self):
        viewers = self.client.application.config["PAGE_VIEWERS"]
        for kind in ("tempdb", "adr"):
            viewer = viewers[kind]
            connection = Mock()
            page = (["ParentObject", "Object", "Field", "VALUE"], []) if kind == "tempdb" else []
            found = (1, 123, 0, 42, 100) if kind == "tempdb" else (1, 123, 0)
            with self.subTest(kind=kind), \
                    patch.object(viewer, "get_connection", return_value=connection), \
                    patch.object(viewer, "find_page_for_row", return_value=found) as find, \
                    patch.object(viewer, "run_dbcc_page", return_value=page), \
                    patch.object(viewer, "format_page_output", return_value=("<b>Formatted evidence</b>", None)) as formatter:
                if kind == "tempdb":
                    with patch.object(viewer, "get_version_store", return_value=([], [])):
                        response = self.client.post(f"/page-viewer/{kind}", data={"find_row": "42"})
                else:
                    response = self.client.post(f"/page-viewer/{kind}", data={"find_row": "42"})
                self.assertEqual(response.status_code, 200)
                self.assertIn("<b>Formatted evidence</b>", response.get_data(as_text=True))
                formatter.assert_called_once()
                find.assert_called_once_with(connection.cursor.return_value, PRIMARY, "42", "Accounts")
                connection.close.assert_called_once()
                connection.cursor.return_value.execute.assert_called_with("USE master;")
        self.assertEqual(self.runner.mock_calls, [])

    def test_page_viewer_errors_are_visible_and_connections_close(self):
        for kind, viewer in self.client.application.config["PAGE_VIEWERS"].items():
            connection = Mock()
            with self.subTest(kind=kind), \
                    patch.object(viewer, "get_connection", return_value=connection), \
                    patch.object(viewer, "find_page_for_row", side_effect=SqlError("Page lookup failed", "")):
                response = self.client.post(f"/page-viewer/{kind}", data={"find_row": "42"})
                self.assertIn("Page lookup failed", response.get_data(as_text=True))
                connection.close.assert_called_once()
                connection.cursor.return_value.execute.assert_called_with("USE master;")

    def test_page_viewers_release_results_before_returning_to_master(self):
        for kind, viewer in self.client.application.config["PAGE_VIEWERS"].items():
            for failed in (False, True):
                with self.subTest(kind=kind, failed=failed):
                    connection = Mock()
                    cursor = Mock()
                    cleanup_cursor = Mock()

                    def open_cursor():
                        if connection.cursor.call_count == 1:
                            return cursor
                        if not cursor.close.called:
                            raise SqlError("Connection is busy with results for another command", "")
                        return cleanup_cursor

                    connection.cursor.side_effect = open_cursor
                    found = (1, 123, 0, 42, 100) if kind == "tempdb" else (1, 123, 0)
                    page = ([], []) if kind == "tempdb" else []
                    with patch.object(viewer, "get_connection", return_value=connection), \
                            patch.object(viewer, "find_page_for_row", return_value=found,
                                         side_effect=ValueError("Page lookup failed") if failed else None), \
                            patch.object(viewer, "run_dbcc_page", return_value=page), \
                            patch.object(viewer, "format_page_output", return_value=("<b>Page evidence</b>", None)), \
                            patch.object(self.client.application.config["PAGE_VIEWERS"]["tempdb"],
                                         "get_version_store", return_value=([], [])):
                        response = self.client.post(f"/page-viewer/{kind}", data={"find_row": "42"})
                    self.assertEqual(response.status_code, 200)
                    self.assertIn("Page lookup failed" if failed else "<b>Page evidence</b>",
                                  response.get_data(as_text=True))
                    cursor.close.assert_called_once()
                    cleanup_cursor.execute.assert_called_once_with("USE master;")
                    connection.close.assert_called_once()

    def test_adr_wide_row_shows_measured_sizes_and_escaped_text_preview(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["adr"]
        rows = [
            ("Slot 0 Offset 0x1804 Length 680",
             "Slot 0 Column 6 Offset 0x19 Length 600 Length (physical) 600",
             "ComplianceNotes", "UPDATED: full preview beyond eighty characters. " * 3 + "<script>unsafe</script>"),
        ]
        html, _ = viewer.format_page_output(rows, highlight_slot=0)
        self.assertIn("680 bytes", html)
        self.assertIn("600 bytes", html)
        self.assertIn("ComplianceNotes physical column size", html)
        self.assertIn("&lt;script&gt;unsafe&lt;/script&gt;", html)
        self.assertNotIn("<script>unsafe</script>", html)
        self.assertIn("DBCC may truncate", html)
        self.assertIn("not a measured version-diff size or PVS allocation", html)
        self.assertEqual(html.count("UPDATED: full preview beyond eighty characters."), 3)

    def test_adr_wide_row_does_not_invent_missing_sizes(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["adr"]
        html, _ = viewer.format_page_output([("Slot 0", "", "ComplianceNotes", "Preview")], 0)
        self.assertEqual(html.count("Not reported by DBCC"), 2)
        self.assertNotIn("600 bytes", html)

    def test_gamestats_viewer_does_not_load_database_wide_before_images(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["tempdb"]
        connection = Mock()
        with patch.object(viewer, "get_connection", return_value=connection), \
                patch.object(viewer, "find_page_for_row", return_value=(1, 368, 0, 1, None)), \
                patch.object(viewer, "run_dbcc_page", return_value=([], [])), \
                patch.object(viewer, "format_page_output", return_value=("<b>GameStats page</b>", "123")), \
                patch.object(viewer, "format_gamestats_summary", return_value="<b>10 retained versions</b>"), \
                patch.object(viewer, "get_version_store") as versions:
            response = self.client.post("/page-viewer/tempdb", data={
                "database": COWBOYS, "table_name": "GameStats", "find_row": "1",
            })
        html = response.get_data(as_text=True)
        self.assertIn("<b>GameStats page</b>", html)
        self.assertIn("<b>10 retained versions</b>", html)
        self.assertLess(html.index("<b>GameStats page</b>"),
                        html.index("<b>10 retained versions</b>"))
        self.assertNotIn("tempdb version-store evidence", html)
        self.assertNotIn("Database-wide before-images are not loaded here", html)
        self.assertNotIn("version store is <b>empty</b>", html)
        versions.assert_not_called()
        connection.close.assert_called_once()

    def test_gamestats_graph_uses_selected_pointer_and_measured_row_count(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["tempdb"]
        cursor = Mock()
        cursor.fetchone.return_value = (10,)
        rows = [
            ("Slot 0 Offset 0x60 Length 7057", "", "GameId", "1"),
            ("Slot 0 Offset 0x60 Length 7057", "", "Yards", "29"),
            ("Slot 10 Offset 0x60 Length 7057", "", "GameId", "99"),
            ("Slot 10 Offset 0x60 Length 7057", "", "Yards", "999"),
        ]
        pointer = {"pointer_file": "1", "pointer_page": "3048", "pointer_slot": "0"}
        with patch.object(viewer, "parse_version_from_hex", return_value=pointer):
            html = viewer.format_gamestats_summary(cursor, rows, 0, "1")
        self.assertIn('class="chain-count">10<', html)
        self.assertIn("Current GameId 1", html)
        self.assertIn("Yards: 29", html)
        self.assertIn("page 3048", html)
        self.assertNotIn("999", html)
        self.assertIn("not a verified pointer-walk length", html)
        sql = cursor.execute.call_args.args[0]
        self.assertIn("COUNT_BIG(*)", sql)
        self.assertIn("v.rowset_id IN", sql)
        self.assertIn("SUBSTRING(v.record_image_first_part, 5, 4)", sql)
        self.assertNotIn("ORDER BY", sql)

    def test_gamestats_graph_rejects_moved_row_and_shows_zero_honestly(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["tempdb"]
        cursor = Mock()
        with self.assertRaisesRegex(ValueError, "no longer contains"):
            viewer.format_gamestats_summary(cursor, [], 0, "1")
        cursor.execute.assert_not_called()
        cursor.fetchone.return_value = (0,)
        rows = [("Slot 0", "", "GameId", "1")]
        html = viewer.format_gamestats_summary(cursor, rows, 0, "1")
        self.assertIn('class="chain-count">0<', html)
        self.assertIn("No version pointer decoded", html)

    def test_tempdb_viewer_connection_is_autocommit(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["tempdb"]
        with viewer.app.app_context(), patch.object(viewer, "mssql_connect") as connect:
            connection = viewer.get_connection("localhost", PRIMARY, "trusted")
            self.assertIs(connection, connect.return_value)
            self.assertTrue(connection.autocommit)

    def test_embedded_viewers_use_owned_runner_connections(self):
        app = self.client.application
        self.runner.resetting = False
        connection = self.runner.connection.return_value
        for kind, viewer in app.config["PAGE_VIEWERS"].items():
            with self.subTest(kind=kind), app.app_context(), \
                    patch.object(viewer, "mssql_connect") as direct_connect, \
                    patch("app.execute_sql") as sql:
                self.assertIs(viewer.get_connection("localhost", PRIMARY, "trusted"), connection)
                sql.assert_called_once_with(connection, f"USE [{PRIMARY}];")
                direct_connect.assert_not_called()
        self.assertEqual(self.runner.connection.call_count, 2)

    def test_viewer_connection_validation_precedes_opening(self):
        app = self.client.application
        factory = app.config["VIEWER_CONNECTION"]
        self.runner.resetting = False
        with self.assertRaisesRegex(ValueError, "lab databases"):
            factory("outside_database")
        self.runner.resetting = True
        with self.assertRaisesRegex(ValueError, "Reset demo is in progress"):
            factory(PRIMARY)
        self.runner.connection.assert_not_called()

    def test_viewer_database_selection_failure_closes_owned_connection(self):
        self.runner.resetting = False
        with patch("app.execute_sql", side_effect=SqlError("Database unavailable", "")):
            with self.assertRaises(SqlError):
                self.client.application.config["VIEWER_CONNECTION"](PRIMARY)
        self.runner.connection.return_value.close.assert_called_once()

    def test_tempdb_viewer_finds_gamestats_by_game_id(self):
        viewer = self.client.application.config["PAGE_VIEWERS"]["tempdb"]
        cursor = Mock()
        cursor.fetchall.side_effect = [[(1, 123)], [("Slot 0", "", "GameId", "1")]]
        result = viewer.find_page_for_row(cursor, COWBOYS, "1", "GameStats")
        self.assertEqual(result[:4], (1, 123, 0, 1))
        self.assertIn("dbo.GameStats", cursor.execute.call_args_list[0].args[0])

    def test_rejects_non_json_and_untrusted_host(self):
        self.assertEqual(self.client.post("/api/reset", data="confirmed=true").status_code, 415)
        self.assertEqual(self.client.get("/api/catalog", headers={"Host": "evil.test"}).status_code, 403)

    def test_confirmation_not_coerced_from_string(self):
        self.assertEqual(self.client.post("/api/reset", json={"confirmed": "true"}).status_code, 400)
        self.runner.reset.assert_not_called()

    def test_invalid_run_input(self):
        self.assertEqual(self.client.post("/api/run", json=[]).status_code, 400)
        self.assertEqual(self.client.post("/api/run", json={"step_id": 123}).status_code, 400)

    def test_run_and_reset(self):
        self.runner.run.return_value = "job1"
        result = self.client.post("/api/run", json={"step_id": "s1", "confirmed": True})
        self.assertEqual(result.json, {"job_id": "job1"})
        self.runner.run.assert_called_once_with("s1", True)
        self.assertEqual(self.client.post("/api/reset", json={"confirmed": True}).status_code, 200)

    def test_benchmark_replay_reads_captures_without_sql(self):
        self.assertEqual(self.client.get("/benchmark").status_code, 200)
        result = self.client.get("/api/benchmark")
        self.assertEqual(result.status_code, 200)
        captures = result.json["captures"]
        self.assertEqual(len(captures), 1)
        self.assertEqual({c["benchmark"] for c in captures}, {"inventory"})
        inventory = next(c for c in captures if c["benchmark"] == "inventory")
        self.assertEqual(inventory["table_rows"], 200000)
        self.assertEqual(inventory["configs"][0]["total_executions"], 5045)
        for capture in captures:
            self.assertEqual(len(capture["configs"]), 4)
            self.assertTrue(capture["source"].endswith(".json"))
            self.assertTrue(capture["timestamp"])
            for config in capture["configs"]:
                for name in config["queries"]:
                    workload = capture["workloads"][name]
                    self.assertTrue(workload["sql"].strip())
                    self.assertTrue(workload["source"].endswith(".sql"))
                    expected = "read" if name in ("check_availability", "category_report") else "write"
                    self.assertEqual(workload["kind"], expected)
        self.assertEqual(self.runner.mock_calls, [])

    def test_team_logos_are_served_locally(self):
        for team in ("dallas-stars", "philadelphia-eagles", "dallas-cowboys"):
            with self.subTest(team=team):
                response = self.client.get(f"/static/logos/{team}.png")
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.mimetype, "image/png")
                self.assertTrue(response.data.startswith(b"\x89PNG\r\n\x1a\n"))
                response.close()

    def test_sql_syntax_assets_are_local_and_shared_by_both_pages(self):
        for asset in ("sql-syntax.js", "sql-syntax.css"):
            response = self.client.get(f"/static/{asset}")
            self.assertEqual(response.status_code, 200)
            self.assertTrue(response.data)
            response.close()
            for page in ("/demo/1", "/benchmark"):
                self.assertIn(f"/static/{asset}", self.client.get(page).get_data(as_text=True))
        self.assertEqual(self.runner.mock_calls, [])

    def test_execution_failure_is_visible(self):
        self.runner.run.side_effect = SqlError("Connection failed", "")
        result = self.client.post("/api/run", json={"step_id": "s1"})
        self.assertEqual(result.status_code, 500)
        self.assertIn("Connection failed", result.json["error"])

    def test_dirty_writer_returns_balance_without_ending_transaction(self):
        catalog = self.client.get("/api/catalog").json
        demo = next(d for d in catalog["demos"] if d["id"] == "1")
        step = demo["scenarios"][0]["steps"][7]
        self.assertEqual(step["id"], "1-dirty-writer")
        self.assertEqual(step["session"], "1")
        self.assertRegex(step["sql"], r"(?s)BEGIN TRAN;.*UPDATE dbo.Accounts.*999999\.00.*"
                         r"SELECT N'Writer uncommitted balance' AS Observation, AccountId, Balance\s+"
                         r"FROM dbo.Accounts WHERE AccountId = 1;")
        self.assertNotRegex(step["sql"], r"\b(?:COMMIT|ROLLBACK|NOLOCK)\b")
        self.runner.run.assert_not_called()

    def test_dirty_rollback_returns_restored_writer_balance(self):
        catalog = self.client.get("/api/catalog").json
        demo = next(d for d in catalog["demos"] if d["id"] == "1")
        step = demo["scenarios"][0]["steps"][9]
        self.assertEqual(step["id"], "1-dirty-rollback")
        self.assertEqual(step["session"], "1")
        self.assertRegex(step["sql"], r"(?s)IF @@TRANCOUNT > 0 ROLLBACK;.*"
                         r"SET TRANSACTION ISOLATION LEVEL READ COMMITTED;.*"
                         r"SELECT N'Writer balance after rollback' AS Observation, AccountId, Balance\s+"
                         r"FROM dbo.Accounts WHERE AccountId = 1;")
        self.runner.run.assert_not_called()


class RunnerTests(unittest.TestCase):
    def test_monitor_database_names_match_catalog(self):
        self.assertEqual(DATABASES, (PRIMARY, EAGLES, COWBOYS))

    def test_sql_observation_labels_escape_apostrophes(self):
        self.assertIn("N'Competitor''s committed balance'", _balance(label="Competitor's committed balance"))

    def test_demo_connection_has_no_query_or_idle_expiry(self):
        runner = DemoRunner()
        connection = Mock()
        connection.cursor.return_value = CursorStub()
        with patch("app.connect", return_value=connection) as connect_mock:
            self.assertIs(runner.connection(), connection)
        self.assertTrue(connection.autocommit)
        self.assertEqual(connection.timeout, 0)
        self.assertEqual(connect_mock.call_args.kwargs["timeout"], 5)

    def test_go_batches_preserve_sql(self):
        cursor = CursorStub()
        connection = Mock()
        connection.cursor.return_value = cursor
        results, _ = execute_sql(connection, "SELECT 1;\nGO -- next\nSELECT 2;")
        self.assertEqual(cursor.batches, ["SELECT 1;", "SELECT 2;"])
        self.assertEqual(len(results), 2)
        self.assertEqual(GO.split("SELECT 'GO';"), ["SELECT 'GO';"])

    def test_unknown_step_and_dangerous_confirmation(self):
        runner = DemoRunner()
        runner.steps = {"danger": ("0", {"dangerous": True})}
        with self.assertRaisesRegex(ValueError, "Unknown"):
            runner.run("missing", True)
        with self.assertRaisesRegex(ValueError, "confirmation"):
            runner.run("danger", False)

    def test_configuration_cannot_destroy_active_sessions(self):
        runner = DemoRunner()
        runner.steps = {"config": ("2", {
            "session": "admin", "sql": "ALTER DATABASE demo SET READ_COMMITTED_SNAPSHOT ON;",
        })}
        runner.sessions["1"] = {"busy": False}
        with self.assertRaisesRegex(ValueError, "End demo"):
            runner.run("config", True)

    def test_database_steps_wait_for_configuration_completion(self):
        runner = DemoRunner()
        runner.steps = {"read": ("2", {"session": "1"})}
        runner.sessions["admin"] = {"busy": True, "configuring": True}
        with self.assertRaisesRegex(ValueError, "Wait for database"):
            runner.run("read", False)

    def test_other_demo_requires_end(self):
        runner = DemoRunner()
        runner.active_demo = "1"
        runner.steps = {"different": ("2", {"session": "1"})}
        with self.assertRaisesRegex(ValueError, "End"):
            runner.run("different", True)

    def test_real_error_is_not_expected_conflict(self):
        runner = DemoRunner()
        runner.lock = threading.RLock()
        session = {"connection": Mock(), "busy": True, "name": "1", "cancel_requested": False}
        session["connection"].cursor.side_effect = SqlError("Login failed (18456)", "")
        job = {"_start": 0}
        runner._execute(session, job, {"id": "conflict", "sql": "UPDATE t", "expected_error": 3960})
        self.assertEqual(job["status"], "failed")
        self.assertFalse(session["busy"])

    def test_missing_expected_error_fails(self):
        runner = DemoRunner()
        connection = Mock()
        connection.cursor.return_value = CursorStub()
        session = {"connection": connection, "busy": True, "name": "1", "cancel_requested": False}
        job = {"_start": 0}
        runner._execute(session, job, {"id": "conflict", "sql": "SELECT 1", "expected_error": 3960})
        self.assertEqual(job["status"], "failed")
        self.assertIn("did not occur", job["error"])

    def test_expected_error_uses_sql_error_number_not_message_guessing(self):
        runner = DemoRunner()
        cursor = CursorStub()
        cursor.description = [("captured_error_number",), ("captured_error_message",)]
        cursor.fetchmany = Mock(side_effect=[[(3960, "Localized conflict text")], []])
        connection = Mock()
        connection.cursor.return_value = cursor
        session = {"connection": connection, "busy": True, "name": "1", "cancel_requested": False}
        job = {"_start": 0}
        runner._execute(session, job, {"id": "conflict", "sql": "UPDATE t", "expected_error": 3960})
        self.assertEqual(job["status"], "expected_error")
        self.assertIn("SQL error 3960", job["error"])


if __name__ == "__main__":
    unittest.main()
