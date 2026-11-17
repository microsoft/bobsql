#!/usr/bin/env python3
"""Deploy and compare the common PMC schema using an in-memory Azure CLI token."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

import pyodbc

SQL_COPT_SS_ACCESS_TOKEN = 1256


def database_token() -> bytes:
    result = subprocess.run(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            "https://database.windows.net/",
            "--query",
            "accessToken",
            "--output",
            "tsv",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    encoded = result.stdout.strip().encode("utf-16-le")
    return struct.pack("<I", len(encoded)) + encoded


def connect(server: str, database: str, token: bytes) -> pyodbc.Connection:
    connection_string = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server=tcp:{server},1433;Database={database};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return pyodbc.connect(
        connection_string,
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token},
        autocommit=True,
    )


def schema_fingerprint(connection: pyodbc.Connection) -> str:
    query = """
    WITH TargetTable AS
    (
        SELECT table_definition.object_id,
               schema_definition.name AS SchemaName,
               table_definition.name AS TableName
        FROM sys.tables AS table_definition
        INNER JOIN sys.schemas AS schema_definition
            ON schema_definition.schema_id = table_definition.schema_id
        WHERE schema_definition.name = N'dbo'
          AND table_definition.name IN
          (
              N'SchemaVersion', N'IngestionRun', N'LoadBatch',
              N'SourceObjectLedger', N'Article', N'PassageContent',
              N'ArticlePassage', N'EmbeddingLedger', N'PassageVector',
              N'CorpusSelectionManifest', N'DemoQuery', N'DemoMeasurement'
          )
    ),
    Manifest AS
    (
         SELECT CONCAT(N'TABLE|', target.SchemaName, N'.', target.TableName)
             COLLATE DATABASE_DEFAULT AS Entry
        FROM TargetTable AS target

        UNION ALL

        SELECT CONCAT
        (
            N'COLUMN|', target.SchemaName, N'.', target.TableName, N'|',
            column_definition.column_id, N'|', column_definition.name, N'|',
            type_definition.name, N'|', column_definition.max_length, N'|',
            column_definition.precision, N'|', column_definition.scale, N'|',
            column_definition.is_nullable, N'|', column_definition.is_identity, N'|',
            ISNULL(default_definition.definition, N'')
        ) COLLATE DATABASE_DEFAULT
        FROM TargetTable AS target
        INNER JOIN sys.columns AS column_definition
            ON column_definition.object_id = target.object_id
        INNER JOIN sys.types AS type_definition
            ON type_definition.user_type_id = column_definition.user_type_id
        LEFT JOIN sys.default_constraints AS default_definition
            ON default_definition.object_id = column_definition.default_object_id

        UNION ALL

        SELECT CONCAT
        (
            N'CHECK|', target.SchemaName, N'.', target.TableName, N'|',
            check_definition.name, N'|', check_definition.definition
        ) COLLATE DATABASE_DEFAULT
        FROM TargetTable AS target
        INNER JOIN sys.check_constraints AS check_definition
            ON check_definition.parent_object_id = target.object_id

        UNION ALL

        SELECT CONCAT
        (
            N'KEY|', target.SchemaName, N'.', target.TableName, N'|',
            key_definition.name, N'|', key_definition.type
        ) COLLATE DATABASE_DEFAULT
        FROM TargetTable AS target
        INNER JOIN sys.key_constraints AS key_definition
            ON key_definition.parent_object_id = target.object_id

        UNION ALL

        SELECT CONCAT
        (
            N'FK|', target.SchemaName, N'.', target.TableName, N'|',
            foreign_key.name, N'|', parent_column.name, N'|',
            referenced_schema.name, N'.', referenced_table.name, N'|',
            referenced_column.name, N'|', foreign_key.delete_referential_action, N'|',
            foreign_key.update_referential_action
        ) COLLATE DATABASE_DEFAULT
        FROM TargetTable AS target
        INNER JOIN sys.foreign_keys AS foreign_key
            ON foreign_key.parent_object_id = target.object_id
        INNER JOIN sys.foreign_key_columns AS foreign_key_column
            ON foreign_key_column.constraint_object_id = foreign_key.object_id
        INNER JOIN sys.columns AS parent_column
            ON parent_column.object_id = foreign_key_column.parent_object_id
           AND parent_column.column_id = foreign_key_column.parent_column_id
        INNER JOIN sys.tables AS referenced_table
            ON referenced_table.object_id = foreign_key_column.referenced_object_id
        INNER JOIN sys.schemas AS referenced_schema
            ON referenced_schema.schema_id = referenced_table.schema_id
        INNER JOIN sys.columns AS referenced_column
            ON referenced_column.object_id = foreign_key_column.referenced_object_id
           AND referenced_column.column_id = foreign_key_column.referenced_column_id

        UNION ALL

        SELECT CONCAT
        (
            N'INDEX|', target.SchemaName, N'.', target.TableName, N'|',
            index_definition.name, N'|', index_definition.type_desc, N'|',
            index_definition.is_unique, N'|', ISNULL(index_definition.filter_definition, N''), N'|',
            index_column.key_ordinal, N'|', index_column.is_included_column, N'|',
            column_definition.name
        ) COLLATE DATABASE_DEFAULT
        FROM TargetTable AS target
        INNER JOIN sys.indexes AS index_definition
            ON index_definition.object_id = target.object_id
           AND index_definition.index_id > 0
        INNER JOIN sys.index_columns AS index_column
            ON index_column.object_id = index_definition.object_id
           AND index_column.index_id = index_definition.index_id
        INNER JOIN sys.columns AS column_definition
            ON column_definition.object_id = index_column.object_id
           AND column_definition.column_id = index_column.column_id
    )
    SELECT Entry
    FROM Manifest
    ORDER BY Entry;
    """
    entries = [str(row[0]) for row in connection.execute(query).fetchall()]
    if not entries:
        raise RuntimeError("The schema manifest query returned no rows")
    return hashlib.sha256("\n".join(entries).encode("utf-8")).hexdigest().upper()


def deploy(targets: tuple[str, ...], database: str, schema_path: Path) -> dict[str, str]:
    token = database_token()
    schema_sql = schema_path.read_text(encoding="utf-8")
    fingerprints: dict[str, str] = {}
    for server in targets:
        with connect(server, database, token) as connection:
            connection.execute(schema_sql)
            fingerprints[server] = schema_fingerprint(connection)
    if len(set(fingerprints.values())) != 1:
        raise RuntimeError(f"Schema fingerprints differ: {fingerprints}")
    return fingerprints


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default="caldovadb")
    parser.add_argument(
        "--target",
        action="append",
        dest="targets",
        required=True,
        help="Logical server FQDN (<server>.database.windows.net). Repeat to compare several servers.",
    )
    parser.add_argument(
        "--schema",
        type=Path,
        default=Path(__file__).with_name("01-common-schema.sql.template"),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Required guard acknowledging that the schema will be deployed.",
    )
    args = parser.parse_args()
    if not args.apply:
        parser.error("--apply is required")

    targets = tuple(args.targets)
    fingerprints = deploy(targets, args.database, args.schema)
    print(json.dumps({"database": args.database, "fingerprints": fingerprints}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
