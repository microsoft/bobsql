---
name: sqlserver2025
description: "Select SQL Server 2025 demos for AI embeddings/vector search, JSON, regex, REST, optimized locking, tempdb Resource Governor, ABORT_QUERY_EXECUTION, or ZavaHospital with NVIDIA NIM. Use when working with examples/sqlserver2025."
---

# SQL Server 2025 demonstration collection

## Procedure

1. Read the [collection README](../../../examples/sqlserver2025/readme.md)
   and the chosen feature's local instructions. For AI, select the intended
   provider: Azure AI, OpenAI-compatible endpoints, Ollama, or ONNX.
2. Verify SQL Server 2025 build/edition, compatibility level, sample database,
   and feature prerequisites. Inspect current source for actual model names,
   endpoint contracts, and dimensions rather than assuming old prose is current.
3. Review changes and obtain approval before database writes, configuration
   changes, model deployment/download, credential setup, stress workloads, or
   cloud spending. Keep API keys and master-key secrets outside source.
4. Follow the selected script/session sequence. Validate the specific feature:
   query hints, JSON/regex behavior, locking evidence, resource limits, vector
   index/search results, or REST/model responses.
5. For [ZavaHospital](../../../examples/sqlserver2025/zavahealth/readme.md),
   complete NIM/GPU deployment, readiness, DNS/TLS, and SQL endpoint tests first.
   Then run database build stages before presentation scripts. Use synthetic
   data only; generated responses are not clinical advice.
6. Report observed outputs and failures. Follow the selected cleanup with
   approval; do not remove shared databases, model services, or AKS resources.

AI providers have different network/privacy and runtime requirements. Do not
claim offline behavior or data locality without checking the actual execution
path. Follow [secret checks](../../../SECRET-SCANNING.md).
