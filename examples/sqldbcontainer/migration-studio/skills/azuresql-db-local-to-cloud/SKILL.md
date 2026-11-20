---
name: azuresql-db-local-to-cloud
description: Explain and verify local Azure SQL container to cloud application behavior without overstating parity or granting runtime admin access.
---

# Verify the same application against Azure SQL

Use the existing application and its supported configuration mechanism. Do not
rewrite working application logic to match a generic environment-variable example.

1. Source engine identity does not prove that the target deployment supports
   every preview feature. Require actual target validation.
2. Compare captured source/target row and content evidence, embedding profile and
   vector fidelity, actual stored contacts, identities, JSON, masks, and indexes.
   Rowversion bytes can change during logical migration; stale edit tokens are
   not portable.
3. Validate masking as a restricted runtime principal, not the migration admin.
   Preserve the app role's narrow procedure permissions and lack of UNMASK.
4. Test JSON filtering and real semantic retrieval. Index presence or successful
   retrieval alone does not establish an approximate vector execution plan.
5. Keep local Ollama inference local unless another provider is explicitly
   configured and approved. Moving SQL does not move the embedding model.
6. An application connection switch is a separate approved step after successful
   validation. Retain the protected previous configuration and verify rollback.
7. If connection switching has not been implemented or verified, say so plainly.
   Never imply a disabled wizard control performed a cutover.

The host exposes only sanitized readiness and execution summaries to Copilot.
Use those tools for evidence; do not infer cloud success from local tests.
