#!/usr/bin/env python3
"""Load the curated PMC corpus into the target database.

Embeddings are inserted exactly as exported from the source database, so the small
and large corpora stay in the same vector space.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from deploy_common_schema import connect, database_token

ROOT = Path(__file__).parents[1]
DEFAULT_PACKAGE = ROOT / "staging" / "pmc-curated-v1"

INSERT_DOCUMENTS = """
INSERT dbo.pmc_documents (document_id, pmcid, package_version, title)
SELECT input.DocumentId, input.PmcNumericId, 1, input.Title
FROM OPENJSON(?)
WITH (DocumentId INT '$.DocumentId', PmcNumericId INT '$.PmcNumericId',
      Title NVARCHAR(2000) '$.Title') AS input;
"""

INSERT_CHUNKS = """
INSERT dbo.pmc_chunks (document_id, chunk_number, text_chunk, embedding)
SELECT input.DocumentId, input.ChunkNumber, input.TextChunk,
       CAST(input.EmbeddingJson AS VECTOR(512))
FROM OPENJSON(?)
WITH (DocumentId INT '$.DocumentId', ChunkNumber INT '$.ChunkNumber',
      TextChunk NVARCHAR(MAX) '$.TextChunk',
      EmbeddingJson NVARCHAR(MAX) '$.Embedding' AS JSON) AS input;
"""


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, default=DEFAULT_PACKAGE)
    parser.add_argument("--server", required=True, help="Logical server FQDN.")
    parser.add_argument("--database", required=True)
    parser.add_argument("--batch", type=int, default=100)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    manifest = json.loads((args.package / "manifest.json").read_text(encoding="utf-8"))
    for section, filename in (("documents", "Documents.jsonl"), ("chunks", "Chunks.jsonl")):
        actual = sha256_file(args.package / filename)
        if actual != manifest[section]["sha256"]:
            raise ValueError(f"{filename} does not match the manifest hash")

    documents = [json.loads(line) for line in
                 (args.package / "Documents.jsonl").read_text(encoding="utf-8").splitlines()]
    chunks = [json.loads(line) for line in
              (args.package / "Chunks.jsonl").read_text(encoding="utf-8").splitlines()]

    for document in documents:
        document["PmcNumericId"] = int(document["PmcId"][3:])

    summary = {
        "package": str(args.package),
        "documents": len(documents),
        "chunks": len(chunks),
        "embeddingModel": manifest["embedding"]["model"],
        "dimensions": manifest["embedding"]["dimensions"],
        "target": f"{args.server}/{args.database}",
    }

    if not args.apply:
        print(json.dumps({**summary, "mode": "validation-only", "networkConnectionOpened": False}, indent=2))
        return 0

    with connect(args.server, args.database, database_token()) as connection:
        connection.timeout = 600
        cursor = connection.cursor()
        existing = cursor.execute(
            "SELECT (SELECT COUNT_BIG(*) FROM dbo.pmc_documents), (SELECT COUNT_BIG(*) FROM dbo.pmc_chunks);"
        ).fetchone()
        if existing[0] or existing[1]:
            raise ValueError(f"Target is not empty: {existing[0]} documents, {existing[1]} chunks")

        cursor.execute(INSERT_DOCUMENTS, json.dumps(documents, ensure_ascii=False))
        for start in range(0, len(chunks), args.batch):
            cursor.execute(INSERT_CHUNKS,
                           json.dumps(chunks[start:start + args.batch], ensure_ascii=False))
            if start % 1000 == 0:
                print(f"  loaded {start:,} / {len(chunks):,} chunks")

        loaded = cursor.execute(
            "SELECT (SELECT COUNT_BIG(*) FROM dbo.pmc_documents), (SELECT COUNT_BIG(*) FROM dbo.pmc_chunks);"
        ).fetchone()

    summary["loadedDocuments"] = int(loaded[0])
    summary["loadedChunks"] = int(loaded[1])
    summary["status"] = ("loaded" if int(loaded[0]) == len(documents) and int(loaded[1]) == len(chunks)
                         else "MISMATCH")
    print(json.dumps(summary, indent=2))
    return 0 if summary["status"] == "loaded" else 1


if __name__ == "__main__":
    raise SystemExit(main())
