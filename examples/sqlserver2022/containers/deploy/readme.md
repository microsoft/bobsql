# SQL Server container lifecycle

Numbered PowerShell demonstrations for the
[SQL Server 2022 container collection](../readme.md). They target Docker
Desktop on Windows.

Start with [step1_runsqlcontainer.ps1](step1_runsqlcontainer.ps1), then inspect
the numbered scripts for copying/restoring data, querying SQL, examining
volumes, patching/rollback, command execution, logs, and process information.
Follow numeric order, not alphabetic file order; the numbering has gaps.

Before executing, review image tags, ports, container/volume names, local
backup paths, and authentication. Supply `SQLCMDPASSWORD` privately using
[credential setup](../../../../SECRET-SCANNING.md#supplying-demo-credentials). Confirm each step's
container/database state before proceeding.

Inspect [cleanup.ps1](cleanup.ps1) before running it: removing containers or
volumes can destroy the lab's data.
