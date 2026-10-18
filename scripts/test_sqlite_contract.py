from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "assets" / "migrations"


def migration_file(scope: str, version: int) -> Path:
    if version == 1:
        return MIGRATIONS / scope / "001_initial.sql"
    if scope in {"registry", "workspace"} and version == 2:
        return MIGRATIONS / scope / "002_revision.sql"
    raise AssertionError(f"Unexpected migration {scope} v{version}")


def migrate(connection: sqlite3.Connection, scope: str, start: int, end: int) -> None:
    for version in range(start + 1, end + 1):
        connection.executescript(migration_file(scope, version).read_text(encoding="utf-8"))
        connection.execute(f"PRAGMA user_version = {version}")


def open_office(root: Path) -> tuple[sqlite3.Connection, sqlite3.Connection, sqlite3.Connection]:
    people_path = root / "people_registry.sqlite"
    catalog = sqlite3.connect(root / "catalog.sqlite")
    people = sqlite3.connect(people_path)
    workspace = sqlite3.connect(root / "workspace.sqlite", isolation_level=None)
    for connection in (catalog, people, workspace):
        connection.execute("PRAGMA journal_mode = DELETE")
        connection.execute("PRAGMA synchronous = FULL")
        connection.execute("PRAGMA foreign_keys = ON")
    migrate(catalog, "catalog", 0, 1)
    migrate(people, "registry", 0, 2)
    migrate(workspace, "workspace", 0, 2)
    workspace.execute("ATTACH DATABASE ? AS office_registry", (str(people_path),))
    workspace.execute("PRAGMA office_registry.journal_mode = DELETE")
    workspace.execute("PRAGMA office_registry.synchronous = FULL")
    return catalog, people, workspace


class SqliteContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="mizan-test-")
        self.root = Path(self.temp.name)
        self.catalog, self.people, self.workspace = open_office(self.root)

    def tearDown(self) -> None:
        for connection in (self.workspace, self.people, self.catalog):
            connection.close()
        self.temp.cleanup()

    @staticmethod
    def insert_person(connection: sqlite3.Connection, person_id: str, name: str) -> None:
        connection.execute(
            """INSERT INTO office_registry.people
               (id, kind, display_name, name_normalized, created_at_utc,
                updated_at_utc, revision)
               VALUES (?, 'natural', ?, ?, '2026-10-18T10:00:00+00:00',
                       '2026-10-18T10:00:00+00:00', 1)""",
            (person_id, name, name),
        )

    def add_client(self, person_id: str, engagement_id: str, operation_id: str) -> None:
        self.workspace.execute("BEGIN IMMEDIATE")
        try:
            self.workspace.execute(
                """INSERT INTO main.client_engagements
                   (id, person_id, status, created_at_utc, updated_at_utc,
                    status_changed_at_utc, revision)
                   VALUES (?, ?, 'active', '2026-10-18T10:00:00+00:00',
                           '2026-10-18T10:00:00+00:00',
                           '2026-10-18T10:00:00+00:00', 1)""",
                (engagement_id, person_id),
            )
            self.workspace.execute(
                """INSERT INTO main.operation_receipts
                   (operation_id, engagement_id, completed_at_utc)
                   VALUES (?, ?, '2026-10-18T10:00:00+00:00')""",
                (operation_id, engagement_id),
            )
            self.workspace.execute("COMMIT")
        except Exception:
            self.workspace.execute("ROLLBACK")
            raise

    def test_fresh_database_migrations_create_expected_tables_and_indexes(self) -> None:
        catalog_tables = {
            row[0]
            for row in self.catalog.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        people_tables = {
            row[0]
            for row in self.people.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        workspace_tables = {
            row[0]
            for row in self.workspace.execute(
                "SELECT name FROM main.sqlite_master WHERE type = 'table'"
            )
        }
        self.assertTrue({"workspaces", "catalog_settings"}.issubset(catalog_tables))
        self.assertIn("people", people_tables)
        self.assertTrue({"client_engagements", "operation_receipts"}.issubset(workspace_tables))
        indexes = {
            row[0]
            for row in self.people.execute(
                "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
        }
        self.assertIn("idx_people_name_prefix", indexes)
        self.assertIn("idx_people_phone", indexes)
        self.assertEqual(self.people.execute("PRAGMA user_version").fetchone()[0], 2)
        self.assertEqual(self.workspace.execute("PRAGMA user_version").fetchone()[0], 2)

    def test_identity_and_engagement_are_rolled_back_together(self) -> None:
        self.workspace.execute("BEGIN IMMEDIATE")
        self.insert_person(self.workspace, "person-atomic", "موكل اختبار")
        with self.assertRaises(sqlite3.IntegrityError):
            self.workspace.execute(
                """INSERT INTO main.client_engagements
                   (id, person_id, status, created_at_utc, updated_at_utc,
                    status_changed_at_utc, revision)
                   VALUES ('engagement-bad', 'person-atomic', 'invalid', 't', 't', 't', 1)"""
            )
        self.workspace.execute("ROLLBACK")
        self.assertEqual(
            self.people.execute("SELECT COUNT(*) FROM people WHERE id='person-atomic'").fetchone()[0],
            0,
        )
        self.assertEqual(
            self.workspace.execute("SELECT COUNT(*) FROM client_engagements").fetchone()[0],
            0,
        )

    def test_constraints_reject_missing_required_fields_and_duplicate_relation(self) -> None:
        self.insert_person(self.workspace, "person-one", "موكل اختبار")
        with self.assertRaises(sqlite3.IntegrityError):
            self.workspace.execute(
                """INSERT INTO main.client_engagements
                   (id, person_id, status, created_at_utc, updated_at_utc,
                    status_changed_at_utc, revision)
                   VALUES ('e1', 'person-one', 'pending', 't', 't', 't', 1)"""
            )
        self.add_client("person-one", "engagement-one", "operation-one")
        with self.assertRaises(sqlite3.IntegrityError):
            self.add_client("person-one", "engagement-two", "operation-two")
        with self.assertRaises(sqlite3.IntegrityError):
            self.workspace.execute(
                """INSERT INTO office_registry.people
                   (id, kind, display_name, name_normalized, created_at_utc,
                    updated_at_utc, revision)
                   VALUES ('invalid-kind', 'bad', 'اختبار', 'اختبار', 't', 't', 1)"""
            )

    def test_existing_person_can_be_reused_but_identity_is_not_copied(self) -> None:
        self.insert_person(self.workspace, "person-shared", "شخص اختبار مشترك")
        self.add_client("person-shared", "engagement-a", "operation-a")
        other_path = self.root / "workspace-other.sqlite"
        other = sqlite3.connect(other_path, isolation_level=None)
        other.execute("PRAGMA journal_mode=DELETE")
        other.execute("PRAGMA synchronous=FULL")
        migrate(other, "workspace", 0, 2)
        other.execute("ATTACH DATABASE ? AS office_registry", (str(self.root / "people_registry.sqlite"),))
        other.execute("BEGIN IMMEDIATE")
        other.execute(
            """INSERT INTO main.client_engagements
               (id, person_id, status, created_at_utc, updated_at_utc,
                status_changed_at_utc, revision)
               VALUES ('engagement-b', 'person-shared', 'active', 't', 't', 't', 1)"""
        )
        other.execute("COMMIT")
        self.assertEqual(
            self.workspace.execute("SELECT COUNT(*) FROM client_engagements").fetchone()[0], 1
        )
        self.assertEqual(
            other.execute("SELECT COUNT(*) FROM client_engagements").fetchone()[0], 1
        )
        self.assertEqual(
            self.people.execute("SELECT COUNT(*) FROM people WHERE id='person-shared'").fetchone()[0],
            1,
        )
        other.close()

    def test_archive_preserves_shared_person_and_restore_is_reversible(self) -> None:
        self.insert_person(self.workspace, "person-archive", "موكل أرشيف اختبار")
        self.add_client("person-archive", "engagement-archive", "operation-archive")
        self.workspace.execute(
            "UPDATE client_engagements SET status='archived', revision=revision+1 WHERE id='engagement-archive'"
        )
        self.assertEqual(
            self.workspace.execute("SELECT status FROM client_engagements").fetchone()[0],
            "archived",
        )
        self.assertEqual(self.people.execute("SELECT COUNT(*) FROM people").fetchone()[0], 1)
        self.workspace.execute(
            "UPDATE client_engagements SET status='active', revision=revision+1 WHERE id='engagement-archive'"
        )
        self.assertEqual(
            self.workspace.execute("SELECT status FROM client_engagements").fetchone()[0],
            "active",
        )

    def test_migration_upgrade_preserves_existing_rows(self) -> None:
        registry_v1 = sqlite3.connect(self.root / "registry-v1.sqlite")
        migrate(registry_v1, "registry", 0, 1)
        registry_v1.execute(
            """INSERT INTO people (id, kind, display_name, name_normalized,
               created_at_utc, updated_at_utc)
               VALUES ('legacy-person', 'natural', 'سجل قديم', 'سجل قديم', 't', 't')"""
        )
        registry_v1.commit()
        migrate(registry_v1, "registry", 1, 2)
        row = registry_v1.execute(
            "SELECT display_name, revision FROM people WHERE id='legacy-person'"
        ).fetchone()
        self.assertEqual(row, ("سجل قديم", 1))
        registry_v1.close()

        workspace_v1 = sqlite3.connect(self.root / "workspace-v1.sqlite")
        migrate(workspace_v1, "workspace", 0, 1)
        workspace_v1.execute(
            """INSERT INTO client_engagements
               (id, person_id, status, created_at_utc, updated_at_utc, status_changed_at_utc)
               VALUES ('legacy-engagement', 'legacy-person', 'active', 't', 't', 't')"""
        )
        workspace_v1.commit()
        migrate(workspace_v1, "workspace", 1, 2)
        row = workspace_v1.execute(
            "SELECT person_id, revision FROM client_engagements WHERE id='legacy-engagement'"
        ).fetchone()
        self.assertEqual(row, ("legacy-person", 1))
        workspace_v1.close()

    def test_migration_failure_keeps_data_and_schema_version(self) -> None:
        conn = sqlite3.connect(self.root / "rollback.sqlite")
        migrate(conn, "registry", 0, 1)
        conn.execute(
            """INSERT INTO people (id, kind, display_name, name_normalized,
               created_at_utc, updated_at_utc)
               VALUES ('keep-me', 'natural', 'بيانات اختبار', 'بيانات اختبار', 't', 't')"""
        )
        conn.commit()
        conn.execute("BEGIN")
        conn.execute("ALTER TABLE people ADD COLUMN draft TEXT")
        conn.execute("ROLLBACK")
        self.assertEqual(conn.execute("PRAGMA user_version").fetchone()[0], 1)
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM people WHERE id='keep-me'").fetchone()[0], 1)
        self.assertNotIn("draft", {row[1] for row in conn.execute("PRAGMA table_info(people)")})
        conn.close()

    def test_pagination_is_bounded_and_name_index_exists(self) -> None:
        self.workspace.execute("BEGIN IMMEDIATE")
        for index in range(1200):
            person_id = f"person-{index:04d}"
            self.workspace.execute(
                """INSERT INTO office_registry.people
                   (id, kind, display_name, name_normalized, created_at_utc,
                    updated_at_utc, revision)
                   VALUES (?, 'natural', ?, ?, 't', 't', 1)""",
                (person_id, f"موكل اختبار {index:04d}", f"موكل اختبار {index:04d}"),
            )
            self.workspace.execute(
                """INSERT INTO main.client_engagements
                   (id, person_id, status, created_at_utc, updated_at_utc,
                    status_changed_at_utc, revision)
                   VALUES (?, ?, 'active', 't', 't', 't', 1)""",
                (f"engagement-{index:04d}", person_id),
            )
        self.workspace.execute("COMMIT")
        rows = self.workspace.execute(
            """SELECT p.id FROM main.client_engagements e
               JOIN office_registry.people p ON p.id=e.person_id
               ORDER BY p.name_normalized, e.id LIMIT 26 OFFSET 25"""
        ).fetchall()
        self.assertEqual(len(rows), 26)
        self.assertEqual(
            self.workspace.execute("SELECT COUNT(*) FROM client_engagements").fetchone()[0], 1200
        )

    def test_foreign_keys_and_shared_identity_references_are_valid(self) -> None:
        self.insert_person(self.workspace, "person-valid", "موكل اختبار")
        self.add_client("person-valid", "engagement-valid", "operation-valid")
        self.assertEqual(self.workspace.execute("PRAGMA main.foreign_key_check").fetchall(), [])
        orphaned = self.workspace.execute(
            """SELECT COUNT(*) FROM main.client_engagements e
               LEFT JOIN office_registry.people p ON p.id=e.person_id
               WHERE p.id IS NULL"""
        ).fetchone()[0]
        self.assertEqual(orphaned, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
