# SQL Server 2025 AI Demos

This directory contains demonstrations of SQL Server 2025's AI capabilities, specifically focusing on vector search and semantic similarity using different AI model providers.

## Overview

These demos showcase how SQL Server 2025 can integrate with various AI embedding models to perform vector search on product descriptions using the AdventureWorks database. Each folder demonstrates the same core functionality but uses a different AI provider for generating embeddings.

## Folders

### vector_search_azureai

Demonstrates vector search using **Azure OpenAI** embeddings service. Uses Azure OpenAI's `text-embedding-3-large` model to generate embeddings via REST API. Ideal for enterprise scenarios with Azure integration and managed cloud services.

### vector_search_openai

Demonstrates vector search using **OpenAI-compatible API** endpoints. Works with OpenAI or any OpenAI-compatible service using the `embeddinggemma` model. Provides flexibility for development and testing with various compatible providers.

### vector_search_ollama

Demonstrates vector search using **Ollama** embedding models running locally. Uses Ollama's native API with the `mxbai-embed-large` model. Runs completely on-premises with no external dependencies, making it great for development, testing, and privacy-sensitive scenarios.

### vector_search_onnx

Demonstrates vector search using **ONNX Runtime** with local models. Uses the `all-MiniLM-L6-v2` model in ONNX format for completely offline operation with no network calls required. Provides the best performance for local deployments but requires ONNX Runtime installation.

## Key SQL Server 2025 Features

These demos showcase SQL Server 2025's new AI capabilities including:
- **CREATE EXTERNAL MODEL** for defining AI models from various providers
- **AI_GENERATE_EMBEDDINGS()** for generating vector embeddings from text
- **Vector Indexes** for fast similarity search
- **Vector Distance Functions** for calculating semantic similarity
- **Hybrid Search** combining traditional full-text with semantic vector search

## Choosing a Provider

| Provider | Best For | Pros | Cons |
|----------|----------|------|------|
| **Azure OpenAI** | Enterprise production | High quality, managed service, scalable | Requires Azure subscription, API costs |
| **OpenAI** | General purpose | Good quality, flexible endpoints | Requires API key, network dependency |
| **Ollama** | Local development | Free, private, no API keys needed | Requires local setup, model downloads |
| **ONNX** | High performance local | Fastest, fully offline, no dependencies | Requires ONNX Runtime setup, model conversion |

## Getting Started

Each folder contains its own detailed readme with step-by-step instructions. Choose the provider that best fits your requirements and follow the instructions in that folder's readme.
