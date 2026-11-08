import threading
import unittest
from unittest.mock import Mock, patch

from app import DemoRunner, GO, SqlError, create_app, execute_sql
from catalog import _balance


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

    def test_execution_failure_is_visible(self):
        self.runner.run.side_effect = SqlError("Connection failed", "")
        result = self.client.post("/api/run", json={"step_id": "s1"})
        self.assertEqual(result.status_code, 500)
        self.assertIn("Connection failed", result.json["error"])


class RunnerTests(unittest.TestCase):
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
