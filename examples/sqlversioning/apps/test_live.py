"""Opt-in live rehearsal: python test_live.py --run [--scenario 2b].

Changes ONLY the already-created lab databases. Does not run demo 0 setup.
"""

import argparse
import time
from decimal import Decimal

from app import DemoRunner, create_app, execute_sql
from catalog import DEMOS


def rehearse(scenario: dict) -> None:
    runner = DemoRunner()
    viewer_client = create_app(runner).test_client() if scenario["id"] in ("4a", "4b") else None
    print(f"REHEARSING {scenario['id']}", flush=True)
    try:
        for step in scenario["steps"]:
            if viewer_client is not None and step.get("viewer"):
                viewer = step["viewer"]
                response = viewer_client.post(f"/page-viewer/{viewer['kind']}", data=viewer)
                html = response.get_data(as_text=True)
                expected = "inrow" if scenario["id"] == "4a" else "offrow"
                assert response.status_code == 200 and '<div class="error">' not in html, html
                assert f'class="slot-box has-{expected}"' in html, (
                    f"{step['id']}: expected measured {expected} page evidence")
                print(f"  {step['id']}: measured {expected} page evidence", flush=True)
                continue
            if step.get("requires_clean_sessions"):
                for existing in list(runner.sessions.values()):
                    if existing["busy"]:
                        existing["thread"].join(timeout=180)
                        if existing["busy"]:
                            raise AssertionError("Wait for running SQL before changing database options")
                runner.reset()
            session = runner.sessions.get(step["session"])
            if session and session["busy"]:
                session["thread"].join(timeout=90)
                if session["busy"]:
                    raise AssertionError(f"Previous step is still blocking session {step['session']}")
            job_id = runner.run(step["id"], True)
            session = runner.sessions.get(step["session"])
            if session:
                session["connection"].timeout = 90
                session["thread"].join(timeout=90 if step.get("requires_clean_sessions") else 1)
            job = next(j for j in runner.jobs if j["id"] == job_id)
            if job["status"] in ("failed", "cancelled"):
                raise AssertionError(f"{step['id']}: {job['error']}")
            if step["id"] in ("1-blocked", "2a-hint-blocked", "4a-adr-only-blocked"):
                requests = [row for result in runner.monitor()["result_sets"]
                            if "blocking_session_id" in result["columns"]
                            for row in result["rows"]]
                assert any(row[1] > 0 for row in requests), "Expected a measured blocking relationship"
            if step["id"] == "4a-adr-only-records":
                assert job["status"] == "succeeded", job
                assert all(not result["rows"] for result in job["result_sets"]), (
                    "Expected no off-row Accounts versions; inspect actual placement/prior retained versions")
            if step["id"] == "4b-held":
                assert job["status"] == "succeeded", "RCSI reader blocked on the held writer"
                counts, _ = execute_sql(runner.sessions["2"]["connection"], "SELECT @@TRANCOUNT;")
                assert counts[0]["rows"][0][0] == 1, "The writer must still be uncommitted"
            if step["id"] == "4b-offrow-size":
                stats = next(r for r in job["result_sets"] if "PVS_Size_KB" in r["columns"])
                assert stats["rows"][0][stats["columns"].index("PVS_Size_KB")] > 0, stats
                records = next(r for r in job["result_sets"] if "ObservedOffRowRecords" in r["columns"])
                assert any(row[records["columns"].index("TableName")] == "SavingsAccounts"
                           and row[records["columns"].index("ObservedOffRowRecords")] > 0
                           for row in records["rows"]), records
            print(f"  {step['id']}: {job['status']} "
                  f"({sum(len(r['rows']) for r in job['result_sets'])} evidence rows)", flush=True)
            for old_job in runner.jobs:
                if old_job["status"] in ("failed", "cancelled"):
                    raise AssertionError(f"{old_job['step_id']}: {old_job['error']}")
        for session in list(runner.sessions.values()):
            if session["busy"]:
                session["thread"].join(timeout=90)
        assert all(j["status"] in ("succeeded", "expected_error") for j in runner.jobs), runner.jobs
        expected_balances = {
            "1": {"1-reset": "100", "1-nolock": "1000199", "1-clean": "200"},
            "2b": {"2b-rcsi-first": "1000", "2b-rcsi-second": "2000",
                   "2b-snapshot": "1000", "2b-snapshot-second": "1000", "2b-outside": "2000"},
            "4a": {"4a-reset": "100", "4a-adr-only-blocked": "100", "4a-adr-only-after": "100"},
            "4b": {"4b-reset": "100", "4b-held": "100", "4b-latest": "999.99"},
        }
        for step_id, expected in expected_balances.get(scenario["id"], {}).items():
            job = next(j for j in runner.jobs if j["step_id"] == step_id)
            result = next(r for r in job["result_sets"] if "Balance" in r["columns"])
            measured = Decimal(result["rows"][0][result["columns"].index("Balance")])
            assert measured == Decimal(expected), f"{step_id}: measured {measured}, expected {expected}"
        print(f"PASSED {scenario['id']}", flush=True)
    finally:
        runner.reset()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--scenario")
    args = parser.parse_args()
    if not args.run:
        parser.error("--run is required: this rehearsal changes the three lab databases")
    scenarios = [s for d in DEMOS for s in d["scenarios"]
                 if s["id"] != "0" and (not args.scenario or s["id"] == args.scenario)]
    if not scenarios:
        parser.error("Unknown scenario")
    started = time.monotonic()
    for scenario in scenarios:
        rehearse(scenario)
    print(f"All {len(scenarios)} scenarios passed in {time.monotonic() - started:.1f}s")


if __name__ == "__main__":
    main()
