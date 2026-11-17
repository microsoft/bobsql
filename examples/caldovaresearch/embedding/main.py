"""Query embedding service.

Runs the same model that produced the corpus embeddings, so query vectors land in
the same space. Vectors are L2-normalized to match how the corpus was ingested.
"""

from __future__ import annotations

import os

import numpy as np
from fastapi import FastAPI, HTTPException
from model2vec import StaticModel
from pydantic import BaseModel, Field

MODEL_NAME = os.environ.get("EMBEDDING_MODEL", "minishlab/potion-base-32M")
DIMENSIONS = 512

app = FastAPI(title="Caldova query embedding", version="1.0.0")
model = StaticModel.from_pretrained(MODEL_NAME)


class EmbedRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


class EmbedResponse(BaseModel):
    model: str
    dimensions: int
    normalized: bool
    vector: list[float]


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "model": MODEL_NAME, "dimensions": DIMENSIONS}


@app.post("/embed", response_model=EmbedResponse)
def embed(request: EmbedRequest) -> EmbedResponse:
    vector = np.asarray(model.encode([request.text])[0], dtype=np.float32)
    if vector.shape[0] != DIMENSIONS:
        raise HTTPException(status_code=500, detail=f"Model returned {vector.shape[0]} dimensions")

    norm = float(np.linalg.norm(vector))
    if norm == 0.0:
        raise HTTPException(status_code=422, detail="Query produced an empty vector")
    vector = vector / norm

    return EmbedResponse(
        model=MODEL_NAME,
        dimensions=DIMENSIONS,
        normalized=True,
        vector=[float(value) for value in vector],
    )
