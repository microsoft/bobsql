---
name: inside-transaction-log
description: "Explore SQL Server transaction log files, VLFs, log records, log IO, minimal logging, recovery, truncation, and log management. Use when working with examples/insidetlog or selecting its five transaction-log labs and VLF tests."
---

# Inside the transaction log

## Procedure

1. Read the [collection map](../../../examples/insidetlog/readme.md).
   Choose physical layout, records, IO, recovery, management, or VLF growth.
2. Read the selected walkthrough and scripts before deciding execution order.
   Confirm SQL build, SQL tools, permissions, filesystem/backup paths, and
   any extra inspection utilities.
3. Require an isolated lab and explicit approval for shutdown, restore,
   file manipulation, log rebuilding, large growth, or destructive cleanup.
   Preserve restorable lab backups before recovery experiments.
4. Establish the documented starting database state. Run the selected blocks
   and separate sessions in order, recording actual VLF, log-space, record,
   IO, transaction, or recovery observations at the requested checkpoints.
5. Treat internal DBCC/log-format details as version-sensitive educational
   evidence. Do not turn a lab's file/log-rebuild technique into production
   recovery advice or infer results from historical screenshots.
6. Close transactions, stop drivers, restore the intended lab state, and
   report remaining files/databases rather than deleting them automatically.

Use [secret checks](../../../SECRET-SCANNING.md) before publishing scripts,
backups, or log captures; binary artifacts need independent review.
