# Ward General Hospital

A cumulative Azure SQL Hyperscale demonstration built around a synthetic
hospital workload. One database and one application carry forward through
architecture, AI, security, observability, resiliency, and performance.
This is demonstration software, not a clinical system.

## Learning path

| Area | What it adds |
| --- | --- |
| [Getting started](getting-started/README.md) | Provision Hyperscale, create replicas, build the schema, and seed synthetic data |
| [Architecture](architecture/README.md) | Inspect compute, log service, page servers, storage, and replicas |
| [First app](first-app/README.md) | Run the .NET 10 Blazor chart application locally with passwordless Entra access |
| [AI-ready SQL](ai-ready-sql/README.md) | Add in-engine embeddings, vector search, and grounded chat |
| [Agentic AI](agentic-ai/README.md) | Extend the same application with the approval-gated shift-handoff workflow |
| [Security](security/README.md) | Explore RLS, auditing, and encryption companions |
| [Observability](observability/README.md) | Inspect performance, availability, errors, and engine events |
| [High availability and resiliency](ha-resiliency/README.md) | Test retry behavior, PITR, and geo-secondary scenarios |
| [Performance](performance/README.md) | Scale compute, grow data, and tune JSON and memory-grant workloads |

## Prerequisites

Start with the exact requirements in Getting Started: an Azure subscription,
Azure CLI, PowerShell 7, and SQL connectivity tools. The web application also
requires the .NET 10 SDK. AI, auditing, and resiliency areas have additional
resources, permissions, and prerequisites.

The shared application lives in [first-app/src](first-app/src/readme.md);
later areas do not create independent copies. Follow each area's feature flags
and configuration instructions. Use the `wardgeneral` workspace skill as the
repository-level guide; some inherited walkthroughs name more granular skills
and figures from the original project that are not bundled in this repository.

## Safe execution

Use synthetic data only. Review target subscription, database, identities,
endpoints, and cost before deployment. Obtain explicit approval before scaling,
failover, recovery, geo-replication, or security-policy changes. Inspect scripts
before execution, keep credentials outside source, and use each area's own
verification and cleanup guidance. Captured validation dates in inherited
walkthroughs do not certify a new deployment.
