#!/usr/bin/env python3
"""Create the full-text catalog and index that back keyword and hybrid search.

Full-text DDL cannot run inside a user transaction, so each statement is issued
separately rather than through the templated schema runner.
"""

from __future__ import annotations

import argparse
import time

from deploy_common_schema import connect, database_token

STATEMENTS = [
    ("catalog", """
        IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'CaldovaCatalog')
            CREATE FULLTEXT CATALOG CaldovaCatalog AS DEFAULT;
    """),
    ("index", """
        IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID('dbo.pmc_chunks'))
            CREATE FULLTEXT INDEX ON dbo.pmc_chunks (text_chunk LANGUAGE 1033)
            KEY INDEX UQ_pmc_chunks_chunk_id ON CaldovaCatalog
            WITH CHANGE_TRACKING = AUTO;
    """),
]

STATUS = """
SELECT CAST(FULLTEXTCATALOGPROPERTY('CaldovaCatalog', 'ItemCount') AS INT) AS ItemCount,
       CAST(OBJECTPROPERTYEX(OBJECT_ID('dbo.pmc_chunks'), 'TableFulltextPopulateStatus') AS INT) AS PopulateStatus,
       CAST(OBJECTPROPERTYEX(OBJECT_ID('dbo.pmc_chunks'), 'TableFulltextItemCount') AS INT) AS IndexedRows;
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, help="Logical server FQDN.")
    parser.add_argument("--database", required=True)
    parser.add_argument("--wait-seconds", type=int, default=300)
    args = parser.parse_args()

    with connect(args.server, args.database, database_token()) as connection:
        connection.timeout = 600
        cursor = connection.cursor()
        for label, statement in STATEMENTS:
            cursor.execute(statement)
            print(f"applied {label}")

        deadline = time.time() + args.wait_seconds
        while time.time() < deadline:
            row = cursor.execute(STATUS).fetchone()
            print(f"  populate status={row.PopulateStatus} indexed rows={row.IndexedRows}")
            if row.PopulateStatus == 0 and (row.IndexedRows or 0) > 0:
                print("full-text population complete")
                return 0
            time.sleep(10)

    print("full-text population did not finish within the wait window")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
