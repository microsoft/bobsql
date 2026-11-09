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
