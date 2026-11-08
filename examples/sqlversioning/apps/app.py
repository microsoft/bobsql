"""Local, presenter-controlled SQL Server versioning demonstrations."""

from __future__ import annotations

import argparse
import atexit
from datetime import datetime, timezone
from decimal import Decimal
import logging
import re
import threading
import time
from typing import Any
from uuid import uuid4

from flask import Flask, jsonify, render_template, request
from mssql_python import connect, Error as SqlError

from catalog import DEMOS

LOG = logging.getLogger(__name__)
DATABASES = ("texasrangerswillwinitthisyear", "eaglesdontfly", "howboutthemcowboys")
GO = re.compile(r"^\s*GO\s*(?:--.*)?$", re.IGNORECASE | re.MULTILINE)
ROW_LIMIT = 1000


def json_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, bytes):
        return value.hex()
    return value


def execute_sql(connection: Any, sql: str) -> tuple[list[dict], list[str]]:
    results: list[dict] = []
    messages: list[str] = []
    cursor = connection.cursor()
    try:
        for batch in GO.split(sql):
            if not batch.strip():
                continue
            cursor.execute(batch)
            while True:
                if cursor.description:
                    columns = [column[0] for column in cursor.description]
                    rows = cursor.fetchmany(ROW_LIMIT + 1)
                    truncated = len(rows) > ROW_LIMIT
                    results.append({
                        "columns": columns,
                        "rows": [[json_value(v) for v in row] for row in rows[:ROW_LIMIT]],
                        "truncated": truncated,
                    })
                    if truncated:
                        messages.append(f"Result display limited to {ROW_LIMIT} rows.")
                    while cursor.fetchmany(ROW_LIMIT):
                        pass
                messages.extend(str(item) for item in (cursor.messages or []))
                if not cursor.nextset():
                    break
    finally:
        cursor.close()
    return results, messages


class DemoRunner:
    def __init__(self, server: str = "localhost"):
        self.server = server
        self.context_hex = uuid4().hex
        self.lock = threading.RLock()
        self.sessions: dict[str, dict] = {}
        self.jobs: list[dict] = []
        self.active_demo: str | None = None
        self.resetting = False
        self.steps = {
            step["id"]: (demo["id"], step)
            for demo in DEMOS for scenario in demo["scenarios"] for step in scenario["steps"]
        }

    def connection(self, timeout: int = 0) -> Any:
        connection = connect(
            f"Server={self.server};Database=master;Trusted_Connection=yes;"
            "Encrypt=no;TrustServerCertificate=yes",
            timeout=5,
        )
        connection.autocommit = True
        connection.timeout = timeout
        try:
            execute_sql(connection, f"SET CONTEXT_INFO 0x{self.context_hex};")
        except SqlError:
            connection.close()
            raise
        return connection

    def _new_session(self, name: str) -> dict:
        connection = self.connection()
        try:
            results, _ = execute_sql(connection, "SET NOCOUNT ON; SELECT @@SPID AS spid;")
            return {
                "name": name, "spid": results[0]["rows"][0][0],
                "connection": connection, "busy": False,
                "transaction_count": 0, "thread": None, "cancel_requested": False,
            }
        except (SqlError, IndexError):
            connection.close()
            raise

    def run(self, step_id: str, confirmed: bool) -> str:
        if step_id not in self.steps:
            raise ValueError("Unknown demo step.")
        demo_id, step = self.steps[step_id]
        if step.get("dangerous") and not confirmed:
            raise ValueError("This step changes lab state; explicit confirmation is required.")
        with self.lock:
            if self.resetting:
                raise ValueError("Session cleanup is still in progress.")
            if self.active_demo not in (None, demo_id):
                raise ValueError("End the current demo before switching demo pages.")
            admin = self.sessions.get("admin")
            if admin and admin["busy"] and admin.get("configuring"):
                raise ValueError("Wait for database configuration to finish before running another step.")
            name = step["session"]
            if step.get("requires_clean_sessions") and self.sessions:
                raise ValueError("End demo sessions before configuration/setup steps.")
            if name == "admin":
                changes_configuration = step.get("requires_clean_sessions") or re.search(
                    r"\b(?:ALTER|CREATE|DROP)\s+DATABASE\b", step["sql"], re.IGNORECASE
                )
                if changes_configuration and self.sessions:
                    raise ValueError("End demo sessions before configuration/setup steps.")
            session = self.sessions.get(name)
            if session and session["busy"]:
                raise ValueError(f"Session {name} is already executing a step.")
            if not session:
                session = self._new_session(name)
                self.sessions[name] = session
            session["configuring"] = bool(step.get("requires_clean_sessions"))
            job = {
                "id": str(uuid4()), "step_id": step_id, "title": step["title"],
                "session": name, "status": "running",
                "started_at": datetime.now(timezone.utc).isoformat(),
                "elapsed_ms": 0, "result_sets": [], "messages": [], "error": None,
                "_start": time.monotonic(),
            }
            self.active_demo = demo_id
            self.jobs.append(job)
            session["busy"] = True
            thread = threading.Thread(target=self._execute, args=(session, job, step), daemon=True)
            session["thread"] = thread
            thread.start()
            return job["id"]

    def _execute(self, session: dict, job: dict, step: dict) -> None:
        try:
            sql = step["sql"]
            expected = step.get("expected_error")
            if expected:
                sql = (
                    "BEGIN TRY\n" + sql + "\nEND TRY\nBEGIN CATCH\n"
                    "IF XACT_STATE() <> 0 ROLLBACK;\n"
                    "SELECT ERROR_NUMBER() AS captured_error_number, "
                    "ERROR_MESSAGE() AS captured_error_message;\nEND CATCH;"
                )
            results, messages = execute_sql(session["connection"], sql)
            captured = next(
                (result["rows"][0] for result in results
                 if result["columns"] == ["captured_error_number", "captured_error_message"]
                 and result["rows"]), None,
            )
            if captured:
                status = "expected_error" if captured[0] == expected else "failed"
                error = f"SQL error {captured[0]}: {captured[1]}"
            elif expected:
                status, error = "failed", f"Expected SQL error {expected} did not occur."
            else:
                status, error = "succeeded", None
            with self.lock:
                job.update(result_sets=results, messages=messages, status=status, error=error)
        except SqlError as exc:
            text = str(exc)
            expected = step.get("expected_error")
            matched = expected is not None and re.search(rf"\b{expected}\b", text) is not None
            with self.lock:
                job.update(
                    status="cancelled" if session["cancel_requested"] else
                    ("expected_error" if matched else "failed"), error=text,
                )
            LOG.warning("Step %s: %s", step["id"], text)
        except Exception as exc:
            # A worker failure must be visible; never leave a success-shaped job.
            LOG.exception("Unexpected execution failure for %s", step["id"])
            with self.lock:
                job.update(status="failed", error=str(exc))
        finally:
            with self.lock:
                job["elapsed_ms"] = round((time.monotonic() - job["_start"]) * 1000)
                session["busy"] = False
                if session["name"] == "admin":
                    try:
                        session["connection"].close()
                    except SqlError:
                        LOG.exception("Could not close administration connection")
                    self.sessions.pop("admin", None)

    def _kill_owned(self, session: dict) -> None:
        control = self.connection(timeout=10)
        try:
            cursor = control.cursor()
            try:
                cursor.execute(
                    "SELECT session_id FROM sys.dm_exec_sessions "
                    "WHERE session_id = ? AND context_info = ?",
                    (session["spid"], bytes.fromhex(self.context_hex)),
                )
                owned = cursor.fetchone()
            finally:
                cursor.close()
            if owned:
                execute_sql(control, f"KILL {int(session['spid'])};")
        finally:
            control.close()

    def cancel(self, name: str) -> None:
        with self.lock:
            session = self.sessions.get(name)
            if not session or not session["busy"]:
                raise ValueError("That session has no running command.")
            if self.resetting:
                raise ValueError("Session cleanup is in progress.")
            session["cancel_requested"] = True
            self._kill_owned(session)
        session["thread"].join(timeout=15)
        with self.lock:
            if session["busy"]:
                raise RuntimeError("Cancellation is pending; wait before restarting the session.")
            if self.sessions.get(name) is session:
                session["connection"].close()
                self.sessions.pop(name, None)

    def reset(self) -> None:
        with self.lock:
            if self.resetting:
                raise ValueError("Session cleanup is already in progress.")
            self.resetting = True
            sessions = list(self.sessions.values())
        try:
            for session in sessions:
                if session["busy"]:
                    session["cancel_requested"] = True
                    self._kill_owned(session)
                    session["thread"].join(timeout=15)
                    if session["busy"]:
                        raise RuntimeError("SQL cancellation is still pending; retry End demo.")
                with self.lock:
                    if self.sessions.get(session["name"]) is not session:
                        continue
                if not session["cancel_requested"]:
                    execute_sql(session["connection"], "IF @@TRANCOUNT > 0 ROLLBACK;")
                session["connection"].close()
                with self.lock:
                    self.sessions.pop(session["name"], None)
            with self.lock:
                self.active_demo = None
        finally:
            with self.lock:
                self.resetting = False

    def monitor(self) -> dict:
        connection = self.connection(timeout=5)
        try:
            databases = ",".join(f"N'{name}'" for name in DATABASES)
            # This diagnostic connection is always autocommit and never reads demo tables.
            results, messages = execute_sql(connection, f"""
SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS int) AS product_major_version,
       CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS edition,
       IS_SRVROLEMEMBER('sysadmin') AS is_sysadmin;
SELECT name AS database_name, is_read_committed_snapshot_on AS rcsi,
       snapshot_isolation_state_desc AS snapshot_isolation,
       is_accelerated_database_recovery_on AS adr
FROM sys.databases WHERE name IN ({databases});
SELECT r.session_id, r.blocking_session_id, r.wait_type, r.status, r.command
FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
WHERE s.context_info = 0x{self.context_hex} AND r.session_id <> @@SPID;
SELECT s.session_id, s.open_transaction_count AS transaction_count
FROM sys.dm_exec_sessions s WHERE s.context_info = 0x{self.context_hex} AND s.session_id <> @@SPID;
SELECT DB_NAME(database_id) AS database_name, reserved_space_kb
FROM sys.dm_tran_version_store_space_usage WHERE database_id IN
    (SELECT database_id FROM sys.databases WHERE name IN ({databases}));
SELECT DB_NAME(database_id) AS database_name, persistent_version_store_size_kb
FROM sys.dm_tran_persistent_version_store_stats WHERE database_id IN
    (SELECT database_id FROM sys.databases WHERE name IN ({databases}));
SELECT a.session_id, a.elapsed_time_seconds, a.transaction_sequence_num
FROM sys.dm_tran_active_snapshot_database_transactions a;
""")
            return {"result_sets": results, "messages": messages, "error": None}
        except SqlError as exc:
            LOG.warning("Monitor query failed: %s", exc)
            return {"result_sets": [], "error": str(exc)}
        finally:
            connection.close()

    def state(self) -> dict:
        try:
            monitor = self.monitor()
        except SqlError as exc:
            LOG.warning("Monitor connection failed: %s", exc)
            monitor = {"result_sets": [], "error": str(exc)}
        counts = {}
        for result in monitor["result_sets"]:
            if result["columns"] == ["session_id", "transaction_count"]:
                counts = dict(result["rows"])
        with self.lock:
            sessions = [{
                "name": s["name"], "spid": s["spid"], "busy": s["busy"],
                "transaction_count": counts.get(s["spid"]),
                "configuring": s.get("configuring", False),
            } for s in self.sessions.values()]
            jobs = []
            for job in self.jobs:
                item = {k: v for k, v in job.items() if not k.startswith("_")}
                if job["status"] == "running":
                    item["elapsed_ms"] = round((time.monotonic() - job["_start"]) * 1000)
                jobs.append(item)
            return {"active_demo": self.active_demo, "sessions": sessions,
                    "jobs": jobs, "monitor": monitor}


def create_app(runner: DemoRunner | None = None) -> Flask:
    app = Flask(__name__)
    app.config["TEMPLATES_AUTO_RELOAD"] = True
    runner = runner or DemoRunner()
    app.config["RUNNER"] = runner

    @app.before_request
    def local_only():
        if request.remote_addr not in ("127.0.0.1", "::1"):
            return jsonify(error="This application is local-only."), 403
        if request.host.split(":")[0] not in ("localhost", "127.0.0.1"):
            return jsonify(error="Invalid local host."), 403
        if request.method == "POST":
            if not request.is_json:
                return jsonify(error="A JSON request is required."), 415
            origin = request.headers.get("Origin")
            if origin and origin != request.host_url.rstrip("/"):
                return jsonify(error="Cross-origin execution is not allowed."), 403

    @app.after_request
    def response_headers(response):
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        return response

    @app.get("/")
    @app.get("/demo/<demo_id>")
    def index(demo_id=None):
        if demo_id is not None and demo_id not in {d["id"] for d in DEMOS}:
            return jsonify(error="Unknown demo."), 404
        return render_template("index.html")

    @app.get("/api/catalog")
    def catalog():
        return jsonify(demos=DEMOS, server=runner.server)

    @app.get("/api/state")
    def state():
        return jsonify(runner.state())

    @app.post("/api/run")
    def run():
        body = request.get_json()
        if not isinstance(body, dict) or not isinstance(body.get("step_id"), str):
            return jsonify(error="step_id must be a string."), 400
        return jsonify(job_id=runner.run(body["step_id"], body.get("confirmed") is True))

    @app.post("/api/reset")
    def reset():
        body = request.get_json()
        if not isinstance(body, dict) or body.get("confirmed") is not True:
            return jsonify(error="Confirm closing sessions and rolling back unfinished work."), 400
        runner.reset()
        return jsonify(ok=True)

    @app.post("/api/cancel")
    def cancel():
        body = request.get_json()
        if not isinstance(body, dict) or body.get("session") not in ("admin", "1", "2"):
            return jsonify(error="Invalid session."), 400
        runner.cancel(body["session"])
        return jsonify(ok=True)

    @app.errorhandler(ValueError)
    def invalid_request(exc):
        return jsonify(error=str(exc)), 409

    @app.errorhandler(SqlError)
    @app.errorhandler(RuntimeError)
    def execution_error(exc):
        LOG.error("Request failed: %s", exc)
        return jsonify(error=str(exc)), 500

    return app


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", default="localhost", help="Local SQL Server instance")
    parser.add_argument("--port", type=int, default=5080)
    args = parser.parse_args()
    if not re.fullmatch(r"(localhost|127\.0\.0\.1|\.)(\\[A-Za-z0-9_]+)?", args.server):
        parser.error("Use localhost, 127.0.0.1, or . with an optional local instance name.")
    logging.basicConfig(level=logging.INFO)
    runner = DemoRunner(args.server)

    def cleanup():
        try:
            runner.reset()
        except (SqlError, RuntimeError, ValueError):
            LOG.exception("Shutdown cleanup failed; check SQL sessions before your next demo")

    atexit.register(cleanup)
    create_app(runner).run(host="127.0.0.1", port=args.port, debug=False, threaded=True)


if __name__ == "__main__":
    main()
