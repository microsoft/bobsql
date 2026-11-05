# High Availability and Resiliency — Observe Application Retry During Failover

This demonstration runs a small .NET probe while a manual failover is
triggered against the existing zone-redundant `wardgeneral` database. The probe
references the Ward General App `WardGeneral.Data` project and calls its existing
`RetryPolicy.CreateConnectionProvider()` and
`RetryPolicy.CreateReadOnlyCommandProvider()` methods. It will not copy or
redefine the retry policy, and the Ward General application will not be
changed.

## Files

| File | Purpose |
| --- | --- |
| `check-failover-health.ps1` | Captures current Resource Health for the exact database; the before phase gates the failover. |
| `run-retry-probe.ps1` | Loads Ward General App configuration, runs the finite console probe, displays every line live, and saves the same output to `probe-output.txt`. |
| `trigger-failover.ps1` | Resolves the exact Hyperscale database and previews the failover REST request; `-Execute` sends it. |
| `collect-failover-evidence.ps1` | Uses the captured UTC interval to save Activity Log, post-failover replica, and Azure Monitor evidence. |
| `retry-probe/` | .NET 10 probe that references `WardGeneral.Data` and logs the built-in provider's `Retrying` events. |

## Prerequisites

- Complete the Getting Started `wardgeneral` deployment with its HA replica.
- Configure `WardGeneral__Server` and `WardGeneral__Database` through
   `first-app/wardgeneral.env` or process environment variables.
- Sign in with `az login` and select the subscription containing
   `rg-collierhealth`.
- Install .NET 10.

## Run the demonstration

First, establish that the database is currently Available by using the default
`Before` phase:

```powershell
./ha-resiliency/failover/check-failover-health.ps1
```

The precheck saves `resource-health.json` and must report
`FailoverHealthPrecheck=PASS`. Then preview the exact intrusive operation:

```powershell
./ha-resiliency/failover/trigger-failover.ps1
```

Confirm the subscription, resource ID, database, service tier, and
zone-redundancy setting. Obtain approval for that exact operation before
starting the two-minute clock. Azure permits one manual failover call per
database every 15 minutes. Do not automatically retry a rejected or throttled
request.

After approval, start the probe in the first terminal:

```powershell
./ha-resiliency/failover/run-retry-probe.ps1
```

The two-minute observation window begins after the first successful request,
not while .NET and passwordless authentication initialize. Preserve the
printed `MeasurementEndsUtc`. Wait for several `OK` rows, then immediately use
the second terminal to submit the already-approved failover:

```powershell
./ha-resiliency/failover/trigger-failover.ps1 -Execute
```

Keep the first terminal visible. It prints `RETRY` before each retry,
`RECOVERED` when an operation succeeds after retrying, and `FAILED` only when
the provider exhausts its policy. The final summary reports request, recovery,
failure, and retry-event counts. The launcher first prints `ProbeEvidence`
with the full path to `probe-output.txt`; every terminal line is also written
there as it occurs.

After the probe completes, use its first UTC timestamp as `StartUtc` and its
final UTC timestamp as `EndUtc`:

```powershell
./ha-resiliency/failover/collect-failover-evidence.ps1 `
   -StartUtc '<first probe UTC timestamp>' `
   -EndUtc '<final probe UTC timestamp>'
```

The collector saves the exact database's Activity Log, a post-failover replica
snapshot from Observability's read-only SQL, and Azure Monitor availability,
connection, firewall, and replication-lag metrics. Activity Log and metric
delivery can lag. An empty bounded result means **not yet delivered**, not zero;
rerun the same fixed interval later rather than widening it.

Finally, capture Resource Health again without treating its coarse status as
the client interruption measurement:

```powershell
./ha-resiliency/failover/check-failover-health.ps1 -Phase After
```

The probe:

1. Open a connection and execute one idempotent read on a fixed cadence.
2. Use the same built-in `Microsoft.Data.SqlClient` configurable retry providers
   that Ward General assigns to connection opens and explicitly read-only
   commands. The shared policy extends the driver's baseline with documented
   Azure SQL transport resets and failover subcodes; it does not retry arbitrary
   errors.
3. Subscribe to the provider's `Retrying` event and print the UTC timestamp,
   retry number, SQL error, and next delay.
4. Print successful request latency before, during, and after failover.
5. Summarize successful requests, recovered requests, and operations that
   exhausted the retry policy.

The control-plane script triggers one manual database failover separately
from the probe. The measured interruption is an observation from that run, not
a promised recovery-time objective.

## Boundaries

- Do not change the HA replica count or zone-redundancy setting.
- Do not copy the retry settings out of `WardGeneral.Data`.
- Do not modify the Ward General application.
- Run only an idempotent read; this demonstration does not test write replay.
- Observability owns the replica and Azure Monitor interpretation; this area
   reuses those surfaces for the failover's fixed UTC interval.
- Do not initiate the restart when the before health check reports that
   Resource Health is not `Available`.

## Status

The complete workflow was live-validated on 2026-09-07 against the
zone-redundant 8-vCore Hyperscale `wardgeneral` database. All 93 probe requests
succeeded. One connection open took 11.374 seconds during failover, the SQL
session changed from 54 to 56, and subsequent requests returned to 39–72 ms.
The configurable retry provider emitted no `Retrying` event because the open
remained pending and ultimately succeeded; this is measured behavior, not a
guarantee for future failovers. The post-failover topology showed the former HA
replica promoted to primary, and Azure Monitor reported 100% availability with
zero failed connections for the bounded window.

A later run on 2026-09-07 exposed SQL error 10054 when the failover reset an
established TCP connection. The then-current hand-maintained transient-error
list did not contain 10054, so that operation failed with zero retry events;
the next probe request connected to the new primary and succeeded 14.447 seconds
after the last pre-failover success. `WardGeneral.Data` now uses SqlClient's
built-in baseline plus documented Azure SQL transport resets and failover
subcodes, including 10054. The app and probe build successfully with that fix;
SqlClient 7 also requires the separate
`Microsoft.Data.SqlClient.Extensions.Azure` package for the application's
`ActiveDirectoryDefault` authentication.

The post-fix live failover validation completed on 2026-09-07 with all 26
requests successful. The connection open spanning the failover took 22.564
seconds, the SQL session changed from 77 to 146, and subsequent requests
returned to 51–277 ms. No `Retrying` event fired because the open remained
pending and succeeded; this run therefore validates application continuity
with the corrected production dependencies, but it did not exercise the new
10054 retry-list entry.

Reference: [Microsoft Learn — Configurable retry logic in SqlClient](https://learn.microsoft.com/sql/connect/ado-net/configurable-retry-logic),
accessed 2026-09-07.

Reference: [Microsoft Learn — Built-in retry logic providers in SqlClient](https://learn.microsoft.com/sql/connect/ado-net/internal-retry-logic-providers-sqlclient),
accessed 2026-09-07.

Reference: [Microsoft Learn — Test application fault resiliency](https://learn.microsoft.com/azure/azure-sql/database/high-availability-sla-local-zone-redundancy#test-application-fault-resiliency),
accessed 2026-09-06.
