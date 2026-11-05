---
name: azure-sql-ai
description: "Build or run the Azure SQL AI demo with managed identity, embeddings, DiskANN vector search, and RAG chat from T-SQL. Use when working with examples/azuresqlai or its deploy, setup-demo, and run-demo scripts."
---

# Azure SQL AI demonstration

## Procedure

1. Read the [README](../../../examples/azuresqlai/readme.md), then inspect
   `deploy.ps1`, `setup-demo.ps1`, and `run-demo.ps1` in that collection.
   Resolve paths from `examples/azuresqlai`, not the original `demos` layout.
2. Verify Azure CLI identity/subscription, PowerShell and SQL tooling,
   target-region model availability, permissions, and current database support
   for the SQL AI/vector features used by the scripts.
3. Present target resources and cost implications. Obtain approval before
   deployment, RBAC/firewall changes, dependency installation, or database writes.
   Use managed identity as designed; do not replace it with committed API keys.
4. If deployment is needed, run the reviewed deployment with explicit targets.
   Verify resources, SQL identity, model deployments, and RBAC rather than
   treating successful resource creation as end-to-end readiness.
5. Execute the seven setup SQL stages through the documented runner. Verify
   seeded data, generated embeddings, vector index, and stored procedures.
6. Run the demonstration and inspect semantic-search and grounded-chat results.
   Use synthetic inputs, surface model/network failures, and distinguish plan
   evidence from assumptions about index use.
7. Report verified outputs. Resource-group deletion requires separate approval
   and confirmation that no unrelated resources are owned by that group.

Follow [secret checks](../../../SECRET-SCANNING.md) before publishing changes.
