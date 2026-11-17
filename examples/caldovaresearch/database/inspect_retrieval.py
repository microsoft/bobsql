#!/usr/bin/env python3
"""Inspect what the demo questions actually return, at document level.

The offline precision metric was biased: relevance labels came from the same
keyword search the lexical retriever uses. This prints results for human review
instead, which is what decides whether the demo looks good on stage.
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
RRF_K = 60

# Reference lists and journal front matter match many queries without being useful evidence.
BOILERPLATE = re.compile(
    r"(JOURNAL INFORMATION|NLM Title Abbreviation|Publisher:|EISSN|"
    r"Copyright:|Creative Commons|Received \d{4}|Accepted \d{4}|"
    r"doi\.org/10\.\d+.*doi\.org/10\.\d+)",
    re.IGNORECASE,
)
CITATION_DENSITY = re.compile(r"10\.\d{4,}/")


def is_boilerplate(text: str) -> bool:
    if BOILERPLATE.search(text[:400]):
        return True
    return len(CITATION_DENSITY.findall(text)) >= 3


def tokenize(text: str) -> list[str]:
    return [t for t in re.findall(r"[a-z0-9]+", text.lower()) if len(t) > 2]


def main() -> int:
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
    matrix = np.asarray(vectors, dtype=np.float32)

    usable = np.array([not is_boilerplate(t) for t in texts])
    print(f"corpus: {len(texts):,} chunks, {len(documents)} documents, "
          f"{int(usable.sum()):,} usable after boilerplate filter\n")

    tokens = [tokenize(t) for t in texts]
    df: dict[str, int] = defaultdict(int)
    for token_list in tokens:
        for term in set(token_list):
            df[term] += 1
    lengths = np.array([len(t) for t in tokens], dtype=np.float32)
    average_length = float(lengths.mean()) or 1.0

    model = StaticModel.from_pretrained(MODEL)
    questions = [q for q, _ in TOPICS]
    query_vectors = np.asarray(model.encode(questions), dtype=np.float32)
    query_vectors /= np.linalg.norm(query_vectors, axis=1, keepdims=True)

    for index, question in enumerate(questions):
        similarity = matrix @ query_vectors[index]

        lexical = np.zeros(len(texts), dtype=np.float32)
        for term in set(tokenize(question)):
            if term not in df:
                continue
            idf = np.log(1 + (len(texts) - df[term] + 0.5) / (df[term] + 0.5))
            for position, token_list in enumerate(tokens):
                count = token_list.count(term)
                if count:
                    lexical[position] += idf * (count * 2.5) / (
                        count + 1.5 * (0.25 + 0.75 * lengths[position] / average_length))

        similarity = np.where(usable, similarity, -1.0)
        lexical = np.where(usable, lexical, -1.0)

        fused: dict[int, float] = defaultdict(float)
        for ranking in (np.argsort(-similarity)[:60], np.argsort(-lexical)[:60]):
            for position, chunk in enumerate(ranking):
                fused[int(chunk)] += 1.0 / (RRF_K + position + 1)

        best_per_document: dict[int, tuple[float, int]] = {}
        for chunk, score in fused.items():
            document_id = keys[chunk][0]
            if document_id not in best_per_document or score > best_per_document[document_id][0]:
                best_per_document[document_id] = (score, chunk)

        top = sorted(best_per_document.items(), key=lambda item: -item[1][0])[:3]
        print(f"Q{index + 1}: {question}")
        for document_id, (score, chunk) in top:
            document = documents[document_id]
            snippet = " ".join(texts[chunk].split())[:110]
            print(f"    {document['PmcId']}  cos={similarity[chunk]:.3f}  {document['Title'][:72]}")
            print(f"        {snippet}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
