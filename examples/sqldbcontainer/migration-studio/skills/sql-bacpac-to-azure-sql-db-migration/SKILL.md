---
name: sql-bacpac-to-azure-sql-db-migration
description: Guide an offline, approved BACPAC export and import with real progress, source consistency gates, and explicit failure reporting.
---

# Move actual schema and data

This adapted workflow supports a protected SQL-authenticated local container
source and an already-created empty Azure free-offer database. These are
intentional differences from the pinned upstream instructions. Source credentials
stay in the operation host and never enter agent messages or browser responses.

1. Discover the source through the wizard. Never recreate the container, reseed
   cases, replace embeddings, or assume a hardcoded case count.
2. Explain the offline requirement. Export must not proceed while the source
   can change. A checkbox or stopping one known client alone is not proof of
   consistency. The host must verify its source consistency gate.
3. Require privileged unmasked source access for export; the restricted web user
   is intentionally insufficient. Do not migrate displayed masked contact text.
4. Require current compatible SqlPackage, including the vector name-binding fix
   documented in 170.5.96.0 or later. Do not suppress all schema warnings.
5. The host runs fixed export/import tools only after immutable plan approval.
   Never interpret natural-language instructions as permission for shell access
   or Azure mutation.
6. Show measured stage state, elapsed time, and sanitized tool results. A running
   process is not success, and unknown progress is not a fabricated percentage.
7. On failure or cancellation, distinguish local artifacts, partial target state,
   and source state. Never automatically delete resources or retry imports.
8. Use get_migration_status to report actual state. If execution has not occurred,
   say so. No mock success, assumed export fidelity, or silent feature removal.

Do not request passwords, connection strings, database rows, raw SQL diagnostics,
private code, or embedding vectors in chat. Sensitive troubleshooting stays in
protected local diagnostics, outside the model context.
