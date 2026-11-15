# Application request and response contracts

[TransferModels.cs](TransferModels.cs) defines typed records for transfer
queues/details, clinical source groups, search requests/results, briefing
options/output, citations, health, and audit entries.

These are the contracts shared by HTTP endpoint handlers, the SQL repository,
and browser JSON consumers; this folder contains no database entities,
credentials, or separate executable project.

When changing a contract, keep [Program.cs](../Program.cs),
[data access](../Data/README.md), [browser code](../wwwroot/README.md), and
SQL result shapes consistent. Build the [parent app](../README.md).
