#!/usr/bin/env python3
"""Deploy and validate the Caldova evidence corpus in Azure SQL."""

from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import shutil
import struct
import subprocess
from pathlib import Path

import pyodbc

SQL_COPT_SS_ACCESS_TOKEN = 1256
ROOT = Path(__file__).parents[1]
DEFAULT_CORPUS = ROOT / "corpus" / "pmc-curated-v1"
EXPECTED_DOCUMENTS = 30
EXPECTED_CHUNKS = 2834
EXPECTED_QUESTIONS = 14


def azure_sql_token(subscription_id: str) -> bytes:
    azure_cli = shutil.which("az.cmd") or shutil.which("az")
    if not azure_cli:
        raise RuntimeError("Azure CLI executable was not found on PATH")
    result = subprocess.run(
        [
            azure_cli, "account", "get-access-token", "--subscription", subscription_id,
            "--resource", "https://database.windows.net/", "--query", "accessToken", "--output", "tsv",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    encoded = result.stdout.strip().encode("utf-16-le")
    return struct.pack("<I", len(encoded)) + encoded


def connect(server: str, database: str, subscription_id: str) -> pyodbc.Connection:
    connection_string = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server=tcp:{server},1433;Database={database};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return pyodbc.connect(
        connection_string,
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: azure_sql_token(subscription_id)},
        autocommit=False,
    )


def batches(sql_text: str) -> list[str]:
    result: list[str] = []
    current: list[str] = []
    for line in sql_text.splitlines():
        if line.strip().upper() == "GO":
            if current:
                result.append("\n".join(current))
                current = []
        else:
            current.append(line)
    if current:
        result.append("\n".join(current))
    return result


def execute_script(cursor: pyodbc.Cursor, path: Path) -> None:
    for batch in batches(path.read_text(encoding="utf-8")):
        if batch.strip():
            cursor.execute(batch)


def verify_package(corpus: Path) -> tuple[dict, list[dict], list[dict]]:
    manifest = json.loads((corpus / "manifest.json").read_text(encoding="utf-8"))
    for section_name in ("documents", "chunks"):
        section = manifest[section_name]
        path = corpus / section["path"]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest.lower() != section["sha256"].lower():
            raise RuntimeError(f"{path.name} failed SHA-256 validation")

    documents = [json.loads(line) for line in (corpus / "Documents.jsonl").read_text(encoding="utf-8").splitlines()]
    chunks = [json.loads(line) for line in (corpus / "Chunks.jsonl").read_text(encoding="utf-8").splitlines()]
    if any("Embedding" in chunk for chunk in chunks):
        raise RuntimeError("The local package still contains legacy embeddings")
    if (len(documents), len(chunks), len(manifest["coverage"])) != (
        EXPECTED_DOCUMENTS, EXPECTED_CHUNKS, EXPECTED_QUESTIONS
    ):
        raise RuntimeError("Unexpected corpus or evaluation-set size")
    return manifest, documents, chunks


def configure_external_model(cursor: pyodbc.Cursor, endpoint: str, deployment: str) -> None:
    model_exists = cursor.execute(
        "SELECT COUNT(*) FROM sys.external_models WHERE name = N'CaldovaEvidenceEmbedding';"
    ).fetchone()[0]
    if model_exists:
        row = cursor.execute(
            "SELECT CONVERT(NVARCHAR(MAX), AI_GENERATE_EMBEDDINGS(N'Caldova evidence model validation' "
            "USE MODEL CaldovaEvidenceEmbedding));"
        ).fetchone()
        vector = json.loads(row[0]) if row and row[0] else None
        if not vector or len(vector) != 512:
            raise RuntimeError(f"Expected a 512-dimensional embedding, received {0 if not vector else len(vector)}")
        return

    endpoint = endpoint.rstrip("/") + "/"
    location = (
        f"{endpoint}openai/deployments/{deployment}/embeddings"
        "?api-version=2024-02-01"
    )
    credential_name = endpoint.replace("]", "]]" )
    escaped_location = location.replace("'", "''")
    escaped_model = deployment.replace("'", "''")
    master_key_password = secrets.token_urlsafe(48).replace("'", "")
    sql = f"""
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'{master_key_password}';
IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = N'{endpoint.replace("'", "''")}')
    CREATE DATABASE SCOPED CREDENTIAL [{credential_name}]
        WITH IDENTITY = 'Managed Identity',
        SECRET = '{{"resourceid":"https://cognitiveservices.azure.com"}}';
CREATE EXTERNAL MODEL CaldovaEvidenceEmbedding
WITH
(
    LOCATION = '{escaped_location}',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = '{escaped_model}',
    CREDENTIAL = [{credential_name}],
    PARAMETERS = '{{"dimensions":512,"sql_rest_options":{{"retry_count":10}}}}'
);
"""
    cursor.execute(sql)
    row = cursor.execute(
        "SELECT CONVERT(NVARCHAR(MAX), AI_GENERATE_EMBEDDINGS(N'Caldova evidence model validation' "
        "USE MODEL CaldovaEvidenceEmbedding));"
    ).fetchone()
    vector = json.loads(row[0]) if row and row[0] else None
    if not vector or len(vector) != 512:
        raise RuntimeError(f"Expected a 512-dimensional embedding, received {0 if not vector else len(vector)}")


def load_corpus(cursor: pyodbc.Cursor, manifest: dict, documents: list[dict], chunks: list[dict]) -> None:
    counts = cursor.execute(
        "SELECT (SELECT COUNT_BIG(*) FROM dbo.pmc_documents), (SELECT COUNT_BIG(*) FROM dbo.pmc_chunks);"
    ).fetchone()
    if tuple(counts) == (EXPECTED_DOCUMENTS, EXPECTED_CHUNKS):
        cursor.execute(
            "IF NOT EXISTS (SELECT 1 FROM dbo.corpus_status WHERE status_id = 1) "
            "INSERT dbo.corpus_status "
            "(status_id, corpus_version, embedding_model, embedding_dimensions, loaded_at) "
            "VALUES (1, ?, N'text-embedding-3-small', 512, SYSUTCDATETIME());",
            manifest["format"],
        )
        return
    if tuple(counts) != (0, 0):
        raise RuntimeError(
            f"Target contains a partial or earlier corpus: {counts[0]} documents, {counts[1]} chunks. "
            "Deploy to an empty research database."
        )

    cursor.executemany(
        "INSERT dbo.pmc_documents (document_id, pmcid, title) VALUES (?, ?, ?);",
        [(item["DocumentId"], item["PmcId"], item["Title"]) for item in documents],
    )
    cursor.executemany(
        "INSERT dbo.pmc_chunks (document_id, chunk_number, text_chunk) VALUES (?, ?, ?);",
        [(item["DocumentId"], item["ChunkNumber"], item["TextChunk"]) for item in chunks],
    )
    cursor.execute(
        "INSERT dbo.corpus_status "
        "(status_id, corpus_version, embedding_model, embedding_dimensions, loaded_at) "
        "VALUES (1, ?, N'text-embedding-3-small', 512, SYSUTCDATETIME());",
        manifest["format"],
    )


def generate_embeddings(connection: pyodbc.Connection, batch_size: int) -> None:
    cursor = connection.cursor()
    while True:
        before = cursor.execute("SELECT COUNT_BIG(*) FROM dbo.pmc_chunks WHERE embedding IS NULL;").fetchone()[0]
        if before == 0:
            break
        cursor.execute(
            f"""
WITH Pending AS
(
    SELECT TOP ({batch_size}) embedding, text_chunk
    FROM dbo.pmc_chunks
    WHERE embedding IS NULL
    ORDER BY document_id, chunk_number
)
UPDATE Pending
SET embedding = AI_GENERATE_EMBEDDINGS(text_chunk USE MODEL CaldovaEvidenceEmbedding);
"""
        )
        connection.commit()
        after = cursor.execute("SELECT COUNT_BIG(*) FROM dbo.pmc_chunks WHERE embedding IS NULL;").fetchone()[0]
        if after >= before:
            raise RuntimeError("Embedding generation made no progress; inspect AI REST endpoint diagnostics")
        print(f"Embedded {EXPECTED_CHUNKS - after:,} / {EXPECTED_CHUNKS:,} passages", flush=True)

    cursor.execute("UPDATE dbo.corpus_status SET embedded_at = SYSUTCDATETIME() WHERE status_id = 1;")
    connection.commit()


def create_index_and_procedures(connection: pyodbc.Connection) -> None:
    cursor = connection.cursor()
    exists = cursor.execute(
        "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.pmc_chunks') "
        "AND name = N'IX_pmc_chunks_embedding';"
    ).fetchone()[0]
    if not exists:
        connection.commit()
        connection.autocommit = True
        cursor.execute(
            "CREATE VECTOR INDEX IX_pmc_chunks_embedding ON dbo.pmc_chunks (embedding) "
            "WITH (METRIC = 'COSINE', TYPE = 'DISKANN');"
        )
        connection.autocommit = False
        cursor = connection.cursor()
    execute_script(cursor, ROOT / "database" / "02-retrieval.sql")
    connection.commit()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subscription", required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--database", default="research")
    parser.add_argument("--foundry-endpoint", required=True)
    parser.add_argument("--embedding-deployment", default="text-embedding-3-small")
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--batch-size", type=int, default=25)
    args = parser.parse_args()
    if args.database != "research":
        parser.error("This deployment supports only the research database")
    if args.batch_size < 1 or args.batch_size > 100:
        parser.error("--batch-size must be between 1 and 100")

    manifest, documents, chunks = verify_package(args.corpus)
    with connect(args.server, args.database, args.subscription) as connection:
        cursor = connection.cursor()
        execute_script(cursor, ROOT / "database" / "01-schema.sql")
        connection.commit()
        configure_external_model(cursor, args.foundry_endpoint, args.embedding_deployment)
        connection.commit()
        load_corpus(cursor, manifest, documents, chunks)
        connection.commit()
        generate_embeddings(connection, args.batch_size)
        create_index_and_procedures(connection)

    print(
        f"SQL deployment complete: {EXPECTED_DOCUMENTS} articles, {EXPECTED_CHUNKS:,} embedded passages, "
        "and retrieval procedures."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
