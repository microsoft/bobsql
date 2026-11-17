#!/usr/bin/env python3
"""Compare vector, lexical, and hybrid retrieval on the curated corpus.

Runs entirely on the exported package so search quality can be judged before any
database is touched. Relevance is scored against the document set each demo
question was drawn from.
"""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from model2vec import StaticModel

sys.path.insert(0, str(Path(__file__).parent))
from export_curated_corpus import TOPICS

PACKAGE = Path(__file__).parents[1] / "staging" / "pmc-curated-v1"
MODEL = "minishlab/potion-base-32M"
TOP_K = 5
RRF_K = 60

STOPWORDS = {
    "how", "does", "do", "what", "why", "can", "the", "a", "an", "and", "or", "of", "to",
    "in", "with", "for", "on", "at", "is", "are", "be", "more", "some", "both", "their",
    "that", "this", "it", "its", "from", "by", "as", "than", "into", "about", "people",
    "adults", "during", "later", "early", "life", "risk", "factors", "contribute",
}


def tokenize(text: str) -> list[str]:
    return [t for t in re.findall(r"[a-z0-9]+", text.lower()) if t not in STOPWORDS and len(t) > 2]


def load() -> tuple[dict, list, np.ndarray, list]:
    documents = {}
    for line in (PACKAGE / "Documents.jsonl").read_text(encoding="utf-8").splitlines():
        record = json.loads(line)
        documents[record["DocumentId"]] = record

    keys, texts, vectors = [], [], []
    for line in (PACKAGE / "Chunks.jsonl").read_text(encoding="utf-8").splitlines():
        record = json.loads(line)
        keys.append((record["DocumentId"], record["ChunkNumber"]))
        texts.append(record["TextChunk"])
        vectors.append(record["Embedding"])
    return documents, keys, np.asarray(vectors, dtype=np.float32), texts


def bm25_scores(query_terms: list[str], docs_tokens: list[list[str]], df: dict, n: int) -> np.ndarray:
    """Standard BM25, matching what the SQL side approximates with full-text ranking."""
    k1, b = 1.5, 0.75
    lengths = np.array([len(t) for t in docs_tokens], dtype=np.float32)
    avg = float(lengths.mean()) or 1.0
    scores = np.zeros(len(docs_tokens), dtype=np.float32)
    for term in set(query_terms):
        if term not in df:
            continue
        idf = np.log(1 + (n - df[term] + 0.5) / (df[term] + 0.5))
        for index, tokens in enumerate(docs_tokens):
            tf = tokens.count(term)
            if tf:
                scores[index] += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * lengths[index] / avg))
    return scores


def rank(scores: np.ndarray, limit: int) -> list[int]:
    return list(np.argsort(-scores)[:limit])


def reciprocal_rank_fusion(rankings: list[list[int]], limit: int) -> list[int]:
    fused: dict[int, float] = defaultdict(float)
    for ranking in rankings:
        for position, index in enumerate(ranking):
            fused[index] += 1.0 / (RRF_K + position + 1)
    return [index for index, _ in sorted(fused.items(), key=lambda item: -item[1])[:limit]]


def main() -> int:
    documents, keys, vectors, texts = load()
    print(f"corpus: {len(texts):,} chunks, {len(documents)} documents\n")

    docs_tokens = [tokenize(t) for t in texts]
    df: dict[str, int] = defaultdict(int)
    for tokens in docs_tokens:
        for term in set(tokens):
            df[term] += 1

    coverage = {c["question"]: set(c["documents"])
                for c in json.loads((PACKAGE / "manifest.json").read_text(encoding="utf-8"))["coverage"]}

    model = StaticModel.from_pretrained(MODEL)
    questions = [q for q, _ in TOPICS]
    query_vectors = np.asarray(model.encode(questions), dtype=np.float32)
    query_vectors /= np.linalg.norm(query_vectors, axis=1, keepdims=True)

    totals = {"vector": 0.0, "lexical": 0.0, "hybrid": 0.0}
    for index, question in enumerate(questions):
        expected = coverage.get(question, set())
        similarity = vectors @ query_vectors[index]
        lexical = bm25_scores(tokenize(question), docs_tokens, df, len(docs_tokens))

        vector_rank = rank(similarity, 50)
        lexical_rank = rank(lexical, 50)
        hybrid_rank = reciprocal_rank_fusion([vector_rank, lexical_rank], TOP_K)

        results = {}
        for label, ranking in (("vector", vector_rank[:TOP_K]),
                               ("lexical", lexical_rank[:TOP_K]),
                               ("hybrid", hybrid_rank)):
            hits = sum(1 for r in ranking if keys[r][0] in expected)
            precision = hits / max(1, len(ranking))
            totals[label] += precision
            results[label] = precision

        top_document = documents[keys[hybrid_rank[0]][0]]
        print(f"Q{index + 1:<2} vec={results['vector']:.2f} lex={results['lexical']:.2f} "
              f"hyb={results['hybrid']:.2f}  {top_document['PmcId']} {top_document['Title'][:60]}")

    count = len(questions)
    print("\nmean precision@5")
    for label in ("vector", "lexical", "hybrid"):
        print(f"  {label:<8} {totals[label] / count:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
