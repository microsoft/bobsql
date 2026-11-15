# SQL data access

[CaldovaRepository.cs](CaldovaRepository.cs) is the application's scoped data
access service. It uses `Microsoft.Data.SqlClient`, parameterized SQL and
stored-procedure calls, async disposal, and request cancellation.

It reads queue/detail records, invokes SQL-owned history search and briefing
generation, and retrieves saved citations and ledger audit. Model keys,
embedding requests, prompt construction, and model inference stay in SQL;
the browser and repository do not call Foundry directly.

The connection comes from `ConnectionStrings:Caldova`; see the
[app README](../README.md) for private runtime overrides. SQL permissions and
the deployed procedure/result contracts must match the [database](../../database/README.md).
Missing configuration and SQL failures are surfaced, not replaced with mock data.

Build through the parent app project; this folder is not a separate project.
