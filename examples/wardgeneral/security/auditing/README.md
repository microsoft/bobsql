# Security — Audit the Ward General Application

This optional companion investigation enables Azure SQL Database auditing at
the logical-server level with a dedicated Log Analytics workspace, records a
bounded UTC interval while the reader uses Ward General, and queries the
resulting `SQLSecurityAuditEvents` rows. The `audit-wardgeneral` skill drives
the workflow in two turns so the query uses the exact interval in which the
reader used the application.

## Files

| File | Purpose |
| --- | --- |
| `setup-auditing.ps1` | Creates the tagged workspace and enables the server-level Azure SQL Database auditing policy with Log Analytics as its destination. |
| `probe-session-context.ps1` | Runs a finite same-driver probe that sets and verifies sentinel `SESSION_CONTEXT` values without starting Ward General or reading patient data. |
| `session-context-probe/` | .NET 10 console source for the controlled `Microsoft.Data.SqlClient` probe. |
| `query-audit.kql` | Defines the bounded audit query independently of its PowerShell driver. |
| `query-audit.ps1` | Queries the bounded application interval and displays principal, action, statement, database, result, and UTC time. |
| `teardown-auditing.ps1` | Disables the Security audit destination and removes only resources owned by this example. |

## Run the example

The recommended reader path is the `audit-wardgeneral` skill. Start with:

```text
Start the Ward General audit.
```

The skill previews the billable setup and asks for approval. It then enables
auditing and verifies both the server policy and the generated
`SQLSecurityAuditEvents_*` route on the logical server's `master` database.
The skill stops there; it does not start Ward General.

The underlying setup commands are:

```powershell
./security/auditing/setup-auditing.ps1 -WhatIf
./security/auditing/setup-auditing.ps1
```

After setup, preserve the `AuditStartUtc` value printed by the script. Run Ward
General through the area workflow, use the unit board, and open one patient
chart. Then return to VS Code Chat with:

```text
I opened a patient chart. Find my audit activity.
```

The skill records `AuditEndUtc` and queries a bounded interval with a
five-second guard on each side. The equivalent command shape is:

```powershell
./security/auditing/query-audit.ps1 `
-StartUtc '<AuditStartUtc minus 5 seconds>' `
-EndUtc '<AuditEndUtc plus 5 seconds>'
```

The default query covers the previous 30 minutes and is a fallback only when
the exact start time was not preserved:

```powershell
./security/auditing/query-audit.ps1
```

### Verify session-context auditing without the web app

To test exactly what the audit record exposes for bound
`sp_set_session_context` parameters without running Ward General, run the
finite probe after auditing is enabled:

```powershell
./security/auditing/probe-session-context.ps1
```

The probe uses .NET 10, `Microsoft.Data.SqlClient` 6.0.1,
`ActiveDirectoryDefault`, and the same parameterized setter batch as Ward
General. Its application name is `wardgeneral-audit-probe`, so its rows are
isolated from real application activity. It does not read or change patient
data or database schema. It prints unique sentinel values, verifies them with
`SESSION_CONTEXT` on the same connection, and prints `ProbeStartUtc`,
`ProbeEndUtc`, `AuditQueryStartUtc`, `AuditQueryEndUtc`, and `SessionId`. The
UTC boundaries come from `SYSUTCDATETIME()` on Azure SQL rather than the client
clock. The audit-query boundaries include a fixed five-second guard because an
audit event can be timestamped just before the clock statement returns or just
after the closing clock value. The unique application name and sentinels keep
that guarded interval discriminating.

After audit delivery, inspect the exact probe interval in detailed mode:

```powershell
./security/auditing/query-audit.ps1 `
-StartUtc '<AuditQueryStartUtc>' `
-EndUtc '<AuditQueryEndUtc>' `
-Application 'wardgeneral-audit-probe' `
-Detailed
```

Compare `Statement` and `AdditionalInformation` with the printed
`ExpectedProviderId` and `ExpectedRole`. Live validation on 2026-09-05 showed
that the `RPC COMPLETED` record's `Statement` expands the `sp_executesql` call
and includes both bound values; `AdditionalInformation` was empty. The
documented `AzureDiagnostics` mapping still does not provide a separate
`session_context` column.

The query filters to the application's connection name, `wardgeneral-app`.
Audit delivery is asynchronous. If no rows have arrived, wait a few minutes and
rerun the same fixed interval; do not widen the interval or generate replacement
activity. In the returned rows, find successful `wardgeneral-app` activity for
the unit-board query against `ops.vBedCensus` and a chart request involving
`clinical.GetPatientChart` or `clinical.GetPatientChartByBed`. When Row-Level
Security is enabled, also find the preceding batch that invokes
`sys.sp_set_session_context` on the same `SessionId` as the application query.
That correlation proves the app ran its context setter on that database
session. The `RPC COMPLETED` statement includes the bound `ProviderId` and
`Role` values for the `Microsoft.Data.SqlClient` call shape used by Ward
General. The audit still shows the authenticated database identity rather than
turning the RLS demo's simulated **Viewing as** provider into a database
principal.

When finished, preview teardown. Because teardown disables the audit policy and
removes the generated audit-only diagnostic route if necessary, and deletes
the tagged workspace, perform it only after explicit approval:

```powershell
./security/auditing/teardown-auditing.ps1 -WhatIf
./security/auditing/teardown-auditing.ps1
```

The setup and teardown scripts refuse to replace another audit policy or delete
an unowned workspace. Log Analytics ingestion and retention are billable.

The example explicitly enables completed batches and successful and failed
database authentication. Azure SQL Database auditing records database
activity; it is not the Azure Activity Log, and it cannot record a Microsoft
Entra authentication failure that occurs before a request reaches the
database.

Reference: [Set up Auditing for Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/auditing-setup?view=azuresql),
accessed 2026-09-01.
