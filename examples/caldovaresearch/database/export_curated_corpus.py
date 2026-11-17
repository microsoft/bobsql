#!/usr/bin/env python3
"""Export a small, topically relevant PMC corpus from the large database.

The demo corpus has to answer real semantic questions, so documents are chosen by
topic rather than by lowest identifier. Every chunk keeps the embedding that is
already stored in the source database, so no re-embedding happens here and the
small and large databases stay in the same vector space.

Only articles whose current PMC Open Access license is CC BY or CC0 are exported, so the
committed corpus can be redistributed with attribution (see THIRD-PARTY-NOTICES.md).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

from deploy_common_schema import connect, database_token

ROOT = Path(__file__).parents[1]
DEFAULT_OUTPUT = ROOT / "staging" / "pmc-curated-v1"
PMC_OPEN_DATA = "https://pmc-oa-opendata.s3.amazonaws.com"
REDISTRIBUTABLE_LICENSES = {"CC BY", "CC0"}

# Each demo question maps to title keywords that reliably surface relevant articles.
TOPICS: list[tuple[str, list[str]]] = [
    ("What biological mechanisms connect periodontal inflammation with elevated blood pressure and cardiovascular risk?",
     ["%periodont%", "%blood pressure%"]),
    ("Does improving maternal nutrition during pregnancy reduce impaired fetal growth and adverse birth outcomes?",
     ["%maternal%", "%birth%"]),
    ("How does prolonged exposure to air pollution affect cognitive decline and dementia risk in older adults?",
     ["%air pollution%", "%cognit%"]),
    ("What factors explain why obesity increases the risk of severe respiratory infection?",
     ["%obesity%", "%COVID-19 severity%"]),
    ("How does disruption of the intestinal microbiome influence anxiety and depressive symptoms?",
     ["%microbiom%", "%depress%"]),
    ("Can physical activity slow functional and cognitive deterioration in people with neurodegenerative disease?",
     ["%physical activity%", "%dementia%"]),
    ("Why are children exposed to repeated intestinal infections more likely to experience poor linear growth?",
     ["%stunting%", "%children%"]),
    ("How does social isolation affect mortality and cardiovascular health among older people?",
     ["%social isolation%", "%mortality%"]),
    ("What mechanisms connect chronic psychological stress with increased susceptibility to infectious disease?",
     ["%psychological stress%", "%immune%"]),
    ("Does treatment of chronic inflammatory disease reduce the subsequent risk of cardiovascular events?",
     ["%rheumatoid arthritis%", "%cardiovascular%"]),
    ("How does antibiotic exposure early in life influence later allergic or metabolic disease?",
     ["%antibiotic%", "%infan%"]),
    ("Why do some cancer patients fail to respond to immune-based treatment despite initially showing tumor regression?",
     ["%immunotherapy%", "%resistance%"]),
    ("How does limited access to nutritious food contribute to both obesity and micronutrient deficiency?",
     ["%food insecurity%", "%nutrition%"]),
    ("What maternal, household, and environmental conditions contribute jointly to childhood undernutrition?",
     ["%undernutrition%", "%determinants%"]),
]

SELECT_DOCUMENTS = """
SELECT TOP (?) d.document_id, d.pmcid, d.title
FROM dbo.pmc_documents AS d
WHERE {predicates}
  AND d.title IS NOT NULL
ORDER BY d.document_id;
"""

SELECT_CHUNKS = """
SELECT c.document_id, c.chunk_number, c.text_chunk,
       CAST(c.embedding AS NVARCHAR(MAX)) AS EmbeddingJson
FROM dbo.pmc_chunks AS c
WHERE c.document_id IN ({placeholders})
ORDER BY c.document_id, c.chunk_number;
"""


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def pmc_license(pmcid: str) -> str | None:
    """Return the license code from the latest PMC Open Access metadata version."""
    query = urllib.parse.urlencode({"list-type": "2", "prefix": f"metadata/{pmcid}."})
    with urllib.request.urlopen(f"{PMC_OPEN_DATA}/?{query}", timeout=30) as response:
        keys = re.findall(r"<Key>([^<]+)</Key>", response.read().decode("utf-8"))
    if not keys:
        return None
    latest = max(keys, key=lambda key: int(key.split(".")[1]))
    with urllib.request.urlopen(f"{PMC_OPEN_DATA}/{latest}", timeout=30) as response:
        return json.load(response).get("license_code")


def write_immutable(path: Path, value: bytes) -> None:
    if path.exists() and path.read_bytes() == value:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as handle:
        handle.write(value)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def export(args: argparse.Namespace) -> dict:
    documents: dict[int, dict] = {}
    coverage: list[dict] = []
    licenses: dict[str, str | None] = {}

    with connect(args.server, args.database, database_token()) as connection:
        connection.timeout = args.timeout
        cursor = connection.cursor()

        for question, terms in TOPICS:
            predicates = " AND ".join(["d.title LIKE ?"] * len(terms))
            rows = cursor.execute(
                SELECT_DOCUMENTS.format(predicates=predicates), args.docs_per_topic, *terms
            ).fetchall()
            kept = []
            for row in rows:
                pmcid = f"PMC{int(row.pmcid)}"
                if pmcid not in licenses:
                    licenses[pmcid] = pmc_license(pmcid)
                if licenses[pmcid] not in REDISTRIBUTABLE_LICENSES:
                    print(f"  skipped {pmcid}: license {licenses[pmcid] or 'unknown'}")
                    continue
                kept.append(row)
                documents.setdefault(int(row.document_id), {
                    "DocumentId": int(row.document_id),
                    "PmcId": pmcid,
                    "Title": str(row.title),
                })
            if not kept:
                print(f"   0 docs  {question[:70]} (omitted from coverage)")
                continue
            coverage.append({"question": question, "documents": [int(r.document_id) for r in kept]})
            print(f"  {len(kept):>2} docs  {question[:70]}")

        if not documents:
            raise ValueError("No documents matched the configured topics")

        # The source keeps one row per package version, so the same article can appear twice.
        by_pmcid: dict[str, dict] = {}
        for document in sorted(documents.values(), key=lambda d: d["DocumentId"]):
            by_pmcid.setdefault(document["PmcId"], document)
        canonical = {
            document_id: by_pmcid[document["PmcId"]]["DocumentId"]
            for document_id, document in documents.items()
        }
        coverage = [
            {"question": item["question"],
             "documents": list(dict.fromkeys(canonical[d] for d in item["documents"]))}
            for item in coverage
        ]
        documents = {d["DocumentId"]: d for d in by_pmcid.values()}
        print(f"  {len(documents)} documents after de-duplicating by PMCID")

        document_ids = sorted(documents)
        chunk_rows = []
        batch = 40
        for start in range(0, len(document_ids), batch):
            window = document_ids[start:start + batch]
            placeholders = ",".join("?" * len(window))
            chunk_rows.extend(
                cursor.execute(SELECT_CHUNKS.format(placeholders=placeholders), *window).fetchall()
            )
            print(f"  chunks so far: {len(chunk_rows):,}")

    if len(chunk_rows) > args.max_chunks:
        raise ValueError(f"Selected {len(chunk_rows):,} chunks, above the {args.max_chunks:,} limit")

    chunk_lines: list[bytes] = []
    for row in chunk_rows:
        embedding = json.loads(row.EmbeddingJson)
        if len(embedding) != 512:
            raise ValueError(f"Unexpected embedding width {len(embedding)}")
        payload = {
            "DocumentId": int(row.document_id),
            "ChunkNumber": int(row.chunk_number),
            "TextChunk": str(row.text_chunk),
            "Embedding": embedding,
        }
        chunk_lines.append(json.dumps(payload, ensure_ascii=True, separators=(",", ":")).encode("utf-8") + b"\n")

    document_lines = [
        json.dumps(documents[document_id], ensure_ascii=True, separators=(",", ":")).encode("utf-8") + b"\n"
        for document_id in document_ids
    ]

    chunk_bytes = b"".join(chunk_lines)
    document_bytes = b"".join(document_lines)
    manifest = {
        "format": "pmc-curated-v1",
        "source": {"collection": "PMC Open Access Subset", "licenses": sorted(REDISTRIBUTABLE_LICENSES)},
        "embedding": {
            "model": "minishlab/potion-base-32M",
            "runtime": "model2vec",
            "runtimeVersion": "0.9.0",
            "dimensions": 512,
            "dtype": "float32",
            "normalized": True,
            "note": "Embeddings are copied verbatim from the source database; nothing is re-encoded here.",
        },
        "documents": {"path": "Documents.jsonl", "rows": len(document_lines),
                      "bytes": len(document_bytes), "sha256": sha256_bytes(document_bytes)},
        "chunks": {"path": "Chunks.jsonl", "rows": len(chunk_lines),
                   "bytes": len(chunk_bytes), "sha256": sha256_bytes(chunk_bytes)},
        "coverage": coverage,
    }
    manifest_bytes = (json.dumps(manifest, ensure_ascii=True, indent=2) + "\n").encode("utf-8")

    args.output.mkdir(parents=True, exist_ok=True)
    write_immutable(args.output / "Documents.jsonl", document_bytes)
    write_immutable(args.output / "Chunks.jsonl", chunk_bytes)
    write_immutable(args.output / "manifest.json", manifest_bytes)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, help="Source logical server FQDN.")
    parser.add_argument("--database", required=True, help="Source database holding the corpus.")
    parser.add_argument("--docs-per-topic", type=int, default=3)
    parser.add_argument("--max-chunks", type=int, default=10_000)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    args.output = args.output.resolve()

    manifest = export(args)
    print(json.dumps({k: v for k, v in manifest.items() if k != "coverage"}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
