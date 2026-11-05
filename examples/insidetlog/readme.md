# Inside the SQL Server transaction log

Explore transaction log layout, records, IO, recovery, and management using
SQL scripts and supporting lab utilities.

| Folder | Walkthrough |
| --- | --- |
| [Demo 1 - Transaction Log File](<Demo 1 - Transaction Log File/readme.md>) | Physical files, VLF allocation, and log headers |
| [Demo 2 - Log Records](<Demo 2 - Log Records/readme.md>) | Read and reason about log records |
| [Demo 3 - Log IO](<Demo 3 - Log IO/readme.md>) | Observe log writes and IO behavior |
| [Demo 4 - Recovery](<Demo 4 - Recovery/readme.md>) | Minimal logging and recovery |
| [Demo 5 - Log Management](<Demo 5 - Log Management/readme.md>) | Truncation, backups, and advanced management |
| [VLF Test](<VLF Test/readme.md>) | Additional growth and open-transaction experiments |

## Prerequisites and safety

Use an isolated SQL Server lab instance and SSMS/sqlcmd. Some exercises require
administrative permissions, local file access, server shutdown, backup files,
or additional inspection tools. Check the selected walkthrough's SQL version
assumptions and hard-coded file paths first.

Start with Demo 1, then choose the relevant topic. Stop at each observation
point; do not batch-run file manipulation or log-rebuild experiments. Internal
DBCC/log-inspection behavior is version-sensitive and not a production repair
procedure. Preserve lab backups, close outstanding transactions, and follow
the selected walkthrough's cleanup instructions.

Use the `inside-transaction-log` workspace skill to navigate the collection.
