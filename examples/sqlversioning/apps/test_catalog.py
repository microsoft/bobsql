"""Catalog-only tests: no SQL Server, web framework or driver is imported."""

import importlib.util
from pathlib import Path
import re
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("versioning_catalog", HERE / "catalog.py")
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


class CatalogTests(unittest.TestCase):
    def test_rcsi_walkthrough_only_prepares_account_one(self):
        steps = catalog.S2A["steps"]
        self.assertNotIn("2a-other-baselines", [step["id"] for step in steps])
        self.assertEqual([step["id"] for step in steps[:3]],
                         ["2a-configure", "2a-reset", "2a-writer"])
        self.assertNotIn("100,200", "\n".join(step["sql"] for step in steps))

    def setUp(self):
        self.scenarios = {
            scenario["id"]: scenario
            for demo in catalog.DEMOS for scenario in demo["scenarios"]
        }
        self.steps = {
            step["id"]: step
            for scenario in self.scenarios.values() for step in scenario["steps"]
        }

    def test_demo_and_subdemo_coverage(self):
        self.assertEqual([demo["id"] for demo in catalog.DEMOS], list("01234"))
        self.assertEqual(
            set(self.scenarios),
            {"0", "1", "2a", "2b", "2c", "2d", "2e",
             "3a", "3b", "3c", "4a", "4b", "4c", "4d", "4e"},
        )
        for demo in catalog.DEMOS:
            self.assertTrue(demo["title"])
            self.assertTrue(demo["description"])
            for scenario in demo["scenarios"]:
                self.assertTrue(scenario["id"].startswith(demo["id"]))
                self.assertGreaterEqual(len(scenario["steps"]), 2)

    def test_numbered_named_folders_match_catalog_sources(self):
        self.assertEqual(len(set(catalog.DEMO_FOLDERS.values())), 5)
        for demo in catalog.DEMOS:
            folder = demo["folder"]
            self.assertEqual(folder, catalog.DEMO_FOLDERS[demo["id"]])
            self.assertTrue(folder.startswith(f"demo{demo['id']}-"))
            self.assertTrue((catalog.ROOT / folder).is_dir())
            self.assertFalse((catalog.ROOT / f"demo{demo['id']}").exists())
            for scenario in demo["scenarios"]:
                for source in scenario["source_files"]:
                    self.assertEqual(Path(source).parts[0], folder)

    def test_unique_ids_and_required_schema(self):
        scenarios = [s for demo in catalog.DEMOS for s in demo["scenarios"]]
        steps = [step for scenario in scenarios for step in scenario["steps"]]
        self.assertEqual(len(scenarios), len(self.scenarios))
        self.assertEqual(len(steps), len(self.steps))
        for scenario in scenarios:
            self.assertIn("End demo", scenario["description"])
            self.assertIn("CLOSE", scenario["description"])
            self.assertIn("cleanup", scenario["description"])
            for step in scenario["steps"]:
                self.assertTrue(step["id"].startswith(scenario["id"] + "-"))
                self.assertIn(step["session"], {"admin", "1", "2"})
                for field in ("id", "title", "sql", "explanation"):
                    self.assertIsInstance(step[field], str)
                    self.assertTrue(step[field].strip())
                for field in ("dangerous", "requires_clean_sessions"):
                    if field in step:
                        self.assertIsInstance(step[field], bool)

    def test_all_original_sql_files_are_attributed_without_viewers(self):
        expected = {
            path.relative_to(catalog.ROOT).as_posix()
            for folder in catalog.DEMO_FOLDERS.values()
            for path in (catalog.ROOT / folder).glob("*.sql")
        }
        actual = set()
        for scenario in self.scenarios.values():
            self.assertTrue(scenario["source_files"])
            for filename in scenario["source_files"]:
                self.assertFalse(Path(filename).is_absolute())
                self.assertNotIn("viewer", filename.lower())
                self.assertTrue((catalog.ROOT / filename).is_file())
                actual.add(filename)
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 25)

    def test_setup_requires_confirmation_and_embeds_original_sql(self):
        steps = self.scenarios["0"]["steps"]
        self.assertEqual(len(steps), 2)
        setup, readiness = steps
        self.assertEqual(setup["session"], "admin")
        self.assertTrue(setup["dangerous"])
        self.assertTrue(setup["requires_clean_sessions"])
        self.assertEqual(setup["title"], "Run setup")
        self.assertIn("APPROVAL REQUIRED", setup["explanation"])
        source = (catalog.ROOT / catalog.DEMO_FOLDERS["0"] / "demo0-setup.sql").read_text(
            encoding="utf-8-sig")
        self.assertTrue(setup["sql"].startswith(source.strip()))
        for database in (catalog.PRIMARY, catalog.EAGLES, catalog.COWBOYS):
            self.assertIn(f"DROP DATABASE {database};", setup["sql"])
            self.assertIn(f"SELECT N'{database}' AS DatabaseName", setup["sql"])
            self.assertIn(f"FROM [{database}].sys.tables", setup["sql"])
        self.assertTrue(setup["sql"].endswith(catalog.SETUP_INVENTORY_SQL.strip()))
        self.assertFalse(readiness.get("dangerous", False))
        self.assertFalse(readiness.get("requires_clean_sessions", False))
        self.assertNotRegex(readiness["sql"], r"\b(?:ALTER|DROP|CREATE|INSERT|UPDATE|DELETE)\b")
        self.assertIn("IF DB_ID", readiness["sql"])
        self.assertIn("ProductMajorVersion", readiness["sql"])

    def test_primary_database_name_is_consistent_across_demo_files(self):
        self.assertEqual(catalog.PRIMARY, "starswillwinthecup")
        for path in catalog.ROOT.rglob("*"):
            if path.is_file() and path.suffix in {".sql", ".py", ".md", ".ps1", ".html", ".json"}:
                with self.subTest(path=path.relative_to(catalog.ROOT)):
                    self.assertNotIn("texasrangers" + "willwin", path.read_text(encoding="utf-8-sig").lower())

    def test_configuration_only_requires_clean_sessions_and_stays_master(self):
        for step in self.steps.values():
            has_alter = re.search(r"\bALTER\s+DATABASE\b", step["sql"], re.I)
            if step["id"] == "0-setup":
                continue
            if has_alter:
                self.assertEqual(step["session"], "admin")
                self.assertTrue(step["dangerous"])
                self.assertTrue(step["requires_clean_sessions"])
                self.assertIn("End demo", step["explanation"])
                self.assertIn("CLOSED", step["explanation"])
            if step.get("requires_clean_sessions"):
                self.assertTrue(has_alter)
            if step["session"] == "admin":
                databases = re.findall(r"\bUSE\s+([^;]+);", step["sql"], re.I)
                self.assertTrue(databases)
                self.assertTrue(all(db.strip().lower() == "master" for db in databases))

    def test_drop_and_data_reset_steps_are_dangerous(self):
        for step in self.steps.values():
            if re.search(r"\bDROP\s+(?:TABLE|INDEX|DATABASE)\b", step["sql"], re.I):
                self.assertTrue(step.get("dangerous"), step["id"])
            if "reset" in step["id"] and step["session"] != "admin":
                self.assertTrue(step.get("dangerous"), step["id"])

    def test_expected_errors_are_explicit_and_only_conflict_steps(self):
        expected = {
            step["id"]: step["expected_error"]
            for step in self.steps.values() if "expected_error" in step
        }
        self.assertEqual(expected, {"2c-conflict": 3960, "2e-scan-conflict": 3960})
        for identifier, code in expected.items():
            step = self.steps[identifier]
            self.assertIs(type(code), int)
            self.assertEqual(step["session"], "1")
            self.assertIn(str(code), step["explanation"])
        self.assertNotIn("expected_error", self.steps["2e-indexed-delete"])
        self.assertIn("IF @@TRANCOUNT > 0 ROLLBACK", self.steps["2c-release"]["sql"])
        self.assertIn("READ COMMITTED", self.steps["2e-scan-rollback"]["sql"])

    def test_blocked_reads_allow_writer_handoff(self):
        for scenario_id, blocked, writer_end in (
            ("1", "1-blocked", "1-writer-commit"),
            ("2a", "2a-hint-blocked", "2a-writer-commit"),
            ("4a", "4a-adr-only-blocked", "4a-adr-only-rollback"),
        ):
            steps = self.scenarios[scenario_id]["steps"]
            identifiers = [step["id"] for step in steps]
            self.assertLess(identifiers.index(blocked), identifiers.index(writer_end))
            self.assertIn("asynchronously", self.steps[blocked]["explanation"])
            self.assertNotEqual(self.steps[blocked]["session"],
                                self.steps[writer_end]["session"])
            self.assertNotIn("WAITFOR", self.steps[blocked]["sql"])
        identifiers = [step["id"] for step in self.scenarios["1"]["steps"]]
        self.assertLess(identifiers.index("1-nolock"), identifiers.index("1-dirty-rollback"))

    def test_balance_labels_and_reproducible_baselines(self):
        for identifier in ("1-reset", "2a-reset", "2b-reset", "2c-reset",
                           "3a-reset", "4a-reset", "4b-reset", "4d-reset"):
            sql = self.steps[identifier]["sql"]
            self.assertIn("Starting committed balance", sql)
            self.assertIn("UPDATE dbo.", sql)
            self.assertIn("WHERE AccountId", sql)
        self.assertIn("1000.00", self.steps["2b-snapshot-reset"]["sql"])
        self.assertIn("ComplianceNotes = DEFAULT", self.steps["4b-wide-reset"]["sql"])
        self.assertIn("Observation", self.steps["4d-sample-current"]["sql"])
        self.assertIn("Balance - 0.01", self.steps["4d-restore-accounts"]["sql"])

    def test_fk_conflict_and_index_fix_are_reproducible(self):
        identifiers = [step["id"] for step in self.scenarios["2e"]["steps"]]
        reset = self.steps["2e-fk-reset"]["sql"]
        self.assertIn("DROP INDEX IF EXISTS IX_OrderItems_OrderId", reset)
        self.assertIn("SET OrderId = 2 WHERE OrderId = 1 OR ItemId = 1", reset)
        self.assertIn("#FkOriginalItems", reset)
        self.assertIn("ChildrenOfDeleteTarget", reset)
        self.assertLess(identifiers.index("2e-scan-rollback"),
                        identifiers.index("2e-index-fix"))
        self.assertLess(identifiers.index("2e-index-fix"),
                        identifiers.index("2e-indexed-snapshot"))
        self.assertLess(identifiers.index("2e-indexed-unrelated-update"),
                        identifiers.index("2e-indexed-delete"))
        self.assertIn("ROLLBACK", self.steps["2e-indexed-rollback"]["sql"])
        self.assertIn("Quantity = b.Quantity", self.steps["2e-restore-items"]["sql"])
        self.assertIn("OUTPUT inserted.OrderId", self.steps["2d-insert"]["sql"])
        self.assertNotIn("SCOPE_IDENTITY", self.steps["2d-remove-insert"]["sql"])

    def test_page_and_chain_evidence_is_real_not_conceptual_counts(self):
        for scenario_id in ("3a", "3b", "4a", "4b"):
            pages = [step for step in self.scenarios[scenario_id]["steps"]
                     if "DBCC PAGE(" in step["sql"]]
            self.assertTrue(pages, scenario_id)
            for step in pages:
                self.assertEqual(step["session"], "admin")
                self.assertEqual(step["viewer"]["kind"], "adr" if scenario_id.startswith("4") else "tempdb")
                self.assertTrue(step["viewer"]["database"])
                self.assertTrue(step["viewer"]["table_name"])
                self.assertTrue(step["viewer"]["find_row"].isdigit())
                self.assertNotIn("BEGIN TRAN", step["sql"])
                self.assertIn("fn_PhysLocCracker", step["sql"])
                self.assertIn("WITH TABLERESULTS", step["sql"])
                self.assertNotIn("requires_clean_sessions", step)
                self.assertFalse(step.get("dangerous", False))
        for key in ("3a-hops-before", "3a-hops-after"):
            self.assertIn("max_version_chain_traversed", self.steps[key]["sql"])
            self.assertIn("WHERE session_id = @@SPID", self.steps[key]["sql"])
        self.assertIn("prev_row_in_chain", self.steps["4a-records-2"]["sql"])
        self.assertIn("row_version", self.steps["4b-offrow-records"]["sql"])
        for step in self.steps.values():
            self.assertNotRegex(step["sql"], r"SELECT\s+[123]\s+AS\s+(?:Chain|Hops)")

    def test_watermark_writers_and_monitors_do_not_share_reader_transaction(self):
        for identifier in ("4d-batch-a", "4d-batch-b", "4d-accounts",
                           "4e-wave-a", "4e-wave-b", "4e-ghost-delete",
                           "4c-other-db-update", "3c-delete"):
            self.assertEqual(self.steps[identifier]["session"], "2")
            self.assertNotIn("BEGIN TRAN", self.steps[identifier]["sql"])
        for step in self.steps.values():
            if "FROM sys.dm_tran_persistent_version_store_stats" in step["sql"]:
                self.assertNotIn("BEGIN TRAN", step["sql"], step["id"])
                self.assertNotEqual(step["session"], "1")
        self.assertEqual(self.steps["4a-adr-only-records"]["session"], "admin")

    def test_ghost_restoration_preserves_original_ids_and_foreign_keys(self):
        sql = self.steps["3c-restore-exact-seed"]["sql"]
        for table in ("Accounts", "Orders", "OrderItems"):
            self.assertIn(f"SET IDENTITY_INSERT dbo.{table} ON", sql)
            self.assertIn(f"SET IDENTITY_INSERT dbo.{table} OFF", sql)
        self.assertLess(sql.index("INSERT dbo.Accounts"), sql.index("INSERT dbo.Orders"))
        self.assertLess(sql.index("INSERT dbo.Orders"), sql.index("INSERT dbo.OrderItems"))
        self.assertIn("SET IDENTITY_INSERT dbo.BigTable ON",
                      self.steps["4e-restore-deletes"]["sql"])

    def test_all_scenarios_explicitly_cleanup_both_connections(self):
        for scenario in self.scenarios.values():
            if scenario["id"] == "0":
                continue
            cleanup = scenario["steps"][-2:]
            self.assertEqual([step["session"] for step in cleanup], ["1", "2"])
            for step in cleanup:
                self.assertIn("IF @@TRANCOUNT > 0 ROLLBACK", step["sql"])
                self.assertIn("READ COMMITTED", step["sql"])
                self.assertIn("USE master", step["sql"])
                self.assertIn("End demo", step["explanation"])

    def test_manual_large_workload_is_dangerous_and_no_automatic_crash(self):
        for identifier in ("4e-traditional-large-update", "4e-adr-large-update",
                           "4e-traditional-timed-rollback", "4e-adr-timed-rollback"):
            step = self.steps[identifier]
            self.assertTrue(step["dangerous"])
            self.assertIn("MANUAL", step["title"])
        self.assertIn("RollbackMilliseconds", self.steps["4e-adr-timed-rollback"]["sql"])
        for step in self.scenarios["4e"]["steps"]:
            self.assertNotRegex(step["sql"], r"\b(?:KILL|SHUTDOWN)\b")
        self.assertIn("xp_readerrorlog", self.steps["4e-recovery-log"]["sql"])


if __name__ == "__main__":
    unittest.main()
