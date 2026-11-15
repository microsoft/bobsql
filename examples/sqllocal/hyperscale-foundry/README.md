# Optional Azure SQL Hyperscale and Microsoft Foundry variant

Deploys the shared Caldova schema, synthetic data, packet/skill procedures,
ledger, and chat invocation path to Azure SQL Database Hyperscale. It uses
Microsoft Entra-only SQL authentication and a SQL server managed identity with
`Cognitive Services OpenAI User` access to Foundry. No model API key is needed.

**Billable lab deployment, not a production template.** It does not provision
private networking, application authentication, external ledger digest
verification, or the local Nemotron vector-search layer.

## Prerequisites

- PowerShell 7, Azure CLI signed in to your intended tenant/subscription.
- Permission to create resource groups, SQL resources, model deployments,
  managed identities, firewall rules, and role assignments.
- [go-sqlcmd](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install)
  on PATH for `ActiveDirectoryDefault` authentication.
- Foundry model availability and quota in your chosen region.
- Unique SQL server and Foundry resource names chosen by you.

## Deploy

From the collection root, replace **every** bracketed value:

```powershell
.\hyperscale-foundry\Deploy.ps1 `
    -SubscriptionId '<your-subscription-id>' `
    -ResourceGroup '<your-lab-resource-group>' `
    -SqlServerName '<your-unique-sql-server>' `
    -FoundryResourceName '<your-unique-foundry-resource>' `
    -Location 'westus3'
```

There are no defaults pointing to the presenter's subscription or resources.
The database name is fixed to `CaldovaRegionalCare` because the shared SQL
scripts use that name. Defaults create provisioned **8-vCore Gen5 Hyperscale**,
local backup redundancy, no zone redundancy, and a `gpt-4.1-mini`
`2025-04-14` GlobalStandard deployment with capacity `1`. Confirm availability,
quota, cost, redundancy, and data residency before running. `-ModelDeployment`
renames that deployment; it does not select a different base model.

The wrapper:

1. Selects your subscription and signed-in user as Entra SQL administrator
   when creating a server.
2. Creates missing resources and assigns the server identity Foundry access.
3. Temporarily opens the detected client IP; use `-ClientIp` for a known NAT
   address instead of automatic detection through `api.ipify.org`.
4. Creates schema and seed only when the expected schema marker is missing;
   refreshes ledger, procedures, model configuration, and validation.
5. Passes your Foundry resource and deployment names into the SQLCMD variables
   in [database](database/README.md); no hostname is hard-coded.
6. Attempts to remove its temporary firewall rules in `finally`.

Existing matching resources are reused, **not fully reconciled**. Review all
names and existing contents first; do not target a shared or production
resource group. Abnormal process termination can leave temporary rules behind;
inspect firewall rules after any interruption.

`-UseAzureServicesFirewall` additionally opens a temporary `0.0.0.0` Azure
services rule (broader than this application's identity). Prefer the specific
client rule; use the broader option only in an isolated lab when necessary.

Add `-TestFoundry` to the same command only when you intend a live model call
and a persisted synthetic briefing. Without it, deployment validation does not
prove live inference. Azure resources remain billable after the script exits.

## Connect the app

From the collection root, with your own authenticated Azure identity and SQL
network access:

```powershell
$env:ConnectionStrings__Caldova = 'Server=tcp:<your-unique-sql-server>.database.windows.net,1433;Initial Catalog=CaldovaRegionalCare;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Default;Application Name=Caldova Transfer Center'
.\app\run.ps1
```

The deployment firewall rule is removed on exit; arrange a separate,
appropriately scoped app access path. Remove the environment override when
returning to local SQL. See [app](../app/README.md).

## Cleanup

There is no automated teardown script. Inventory the resources you created,
including SQL server/database, Foundry account/deployment, role assignments,
and any remaining firewall rules. Remove only resources owned by your lab;
delete a resource group only if it was created exclusively for this demo.
Dropping a database permanently discards its saved interactions and audit.
