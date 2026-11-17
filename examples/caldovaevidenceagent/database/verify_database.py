#!/usr/bin/env python3
"""Verify the deployed Azure SQL evidence contract."""

from __future__ import annotations

import argparse

from deploy_database import EXPECTED_CHUNKS, EXPECTED_DOCUMENTS, connect


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subscription", required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--database", default="research")
    args = parser.parse_args()

    with connect(args.server, args.database, args.subscription) as connection:
        cursor = connection.cursor()
        counts = cursor.execute(
            "SELECT (SELECT COUNT_BIG(*) FROM dbo.pmc_documents), "
            "(SELECT COUNT_BIG(*) FROM dbo.pmc_chunks), "
            "(SELECT COUNT_BIG(*) FROM dbo.pmc_chunks WHERE embedding IS NULL);"
        ).fetchone()
        if tuple(counts) != (EXPECTED_DOCUMENTS, EXPECTED_CHUNKS, 0):
            raise RuntimeError(f"Unexpected corpus counts: {tuple(counts)}")

        index_row = cursor.execute(
            "SELECT JSON_VALUE(vector_index.build_parameters, '$.Version'), vector_index.distance_metric "
            "FROM sys.vector_indexes AS vector_index "
            "INNER JOIN sys.indexes AS index_definition ON index_definition.object_id = vector_index.object_id "
            "AND index_definition.index_id = vector_index.index_id "
            "WHERE index_definition.name = N'IX_pmc_chunks_embedding';"
        ).fetchone()
        if not index_row or str(index_row[0]) != "3" or str(index_row[1]).upper() != "COSINE":
            raise RuntimeError(f"Unexpected vector index contract: {index_row}")

        rows = cursor.execute(
            "EXEC dbo.search_evidence @question = ?, @top_k = 3;",
            "How does disruption of the intestinal microbiome influence anxiety and depressive symptoms?",
        ).fetchall()
        if len(rows) != 3 or len({row[0] for row in rows}) != 3:
            raise RuntimeError("search_evidence did not return three distinct articles")

        print("SQL verification passed")
        print(f"  Articles: {EXPECTED_DOCUMENTS}")
        print(f"  Passages: {EXPECTED_CHUNKS:,}")
        print("  Embeddings missing: 0")
        print("  Vector index: IX_pmc_chunks_embedding, version 3, cosine")
        print("  search_evidence: 3 distinct articles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
