# High Availability and Resiliency — High Availability and Resiliency in Hyperscale

High Availability and Resiliency has three guided examples. The first shows what the Ward General
application's existing retry policy does while Azure SQL fails the database
over. The second recovers Ward General data to a point before a controlled
change. The third creates and verifies a cross-region Hyperscale geo-secondary.
Together they cover application availability, data recovery, and regional
resiliency.

| Folder | Question | Status |
| --- | --- | --- |
| [`failover/`](failover/) | How does the same retry provider used by Ward General carry an application request through a manual failover? | Live validated on 2026-09-07 |
| [`pitr/`](pitr/) | How can Ward General create a current-as-of-start, lower-compute Hyperscale serverless copy for isolated testing by using PITR? | Live validated on 2026-09-07 |
| [`geo/`](geo/) | How can Ward General create an Entra-only logical server in another region and add a Hyperscale geo-secondary? | Live validated in East US 2 with CMK on 2026-09-08 |

Start with the README inside the folder for the demonstration being performed.
All three examples use the existing Getting Started `wardgeneral` deployment. The
failover example also references the Ward General App `WardGeneral.Data` project so
the retry settings have one source of truth.

The matching skills are `test-hyperscale-failover`,
`recover-wardgeneral-pitr`, and `deploy-wardgeneral-geo-replica`. They drive the
same commands and approval gates as the READMEs.

The area explains HA replica count, continuous priming, failover groups,
zone redundancy, backup policy, replica lag, maintenance windows, and RPO/RTO
commitments without packaging each topic as another guided example. Observability
remains the source for availability evidence and replica-state diagnostics.

> **New here?** Read the [repository README](../../README.md) first. The examples
> assume the Getting Started `wardgeneral` deployment and synthetic dataset already
> exist.

**All data is synthetic. There is no real patient data (PHI) here.**
