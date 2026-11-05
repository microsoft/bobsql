---
name: wardgeneral
description: "Guide the cumulative Ward General Hospital Azure SQL Hyperscale demo: provision/schema, architecture, .NET 10 Blazor app, SQL AI, agentic shift handoff, security/RLS, observability, failover/PITR/geo, scaling, and tuning. Use for examples/wardgeneral."
---

# Ward General cumulative application

## Procedure

1. Start with the [collection map](../../../examples/wardgeneral/readme.md).
   Identify the requested area and read its README, scripts, and prerequisites.
   The database and application carry forward; do not scaffold a replacement.
2. Verify subscription, identity, target database/replicas, PowerShell/Azure CLI
   tooling, and prior-stage readiness. The app requires .NET 10 and lives in
   [first-app/src](../../../examples/wardgeneral/first-app/src/readme.md).
3. If setup is missing, follow Getting Started's reviewed provisioning,
   replica, schema, seed, and verification stages. Get approval for billable
   resources, role/firewall changes, database writes, or tool installation.
4. For application or AI work, preserve the shared data/retry layer, Entra
   authentication, replica routing, and documented feature flags. Enable AI
   features only after their SQL/models/DAB prerequisites are verified.
5. Distinguish observation from mutation. Architecture/observability evidence
   does not authorize tuning, scaling, failover, recovery, geo-replication,
   or security-policy changes. Use the owning area's preview and approval gates.
6. Verify the requested outcome with that area's SQL, application, plan,
   retry, audit, or resource evidence. Treat previous validation dates and
   captured results as historical, not certification of the current deployment.
7. End workload/probe processes and follow only the approved, area-owned
   cleanup. Never delete the shared database as routine per-area cleanup.

## Scope and safety

Use synthetic data only. Preserve the runtime shift-handoff skill's grounding
and save-approval requirements; it is not the same as this workspace skill.
Inherited references to optional granular skills/figures may not be bundled:
use the actual area scripts and report missing prerequisites explicitly.
Follow [secret checks](../../../SECRET-SCANNING.md) before publishing.
