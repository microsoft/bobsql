# High Availability and Resiliency — Create a Hyperscale Geo-Replica

This demonstration creates a reader-named Entra-only logical server in East
US 2, then creates a Hyperscale geo-secondary of the existing `wardgeneral`
database on it. The source database remains online and writable while
transaction log is replicated asynchronously.

The same workflow supports either TDE configuration a reader can bring from
the preceding areas. If the source uses the default service-managed
protector, no Key Vault work is performed. If Security switched the source to
a customer-managed key (CMK), the script grants the target server identity
access to that existing key and registers the key on the target before it
creates the geo-secondary. It never changes the source protector.

## Files

| File | Purpose |
| --- | --- |
| `deploy-geo-replica.ps1` | Reads the source from Ward General App configuration, previews the exact deployment, then creates the target server and geo-replica with `-Execute`. |
| `verify-geo-replica.ps1` | Verifies the source, target server identity, geo-secondary resource, and replication link from both sides. |
| `cleanup-geo-replica.ps1` | Previews the exact relationship and target resources, then removes the link and target server with `-Execute`. |

## Prerequisites

- Complete the Getting Started `wardgeneral` Hyperscale deployment.
- Fill in `first-app/wardgeneral.env`. This workflow uses
  `WardGeneral__Server` and `WardGeneral__Database` as its source of truth.
- Sign in with `az login` as the Microsoft Entra user who should administer
  the new logical server.
- Select the subscription containing `rg-collierhealth`.
- Ensure the signed-in identity can create SQL servers and databases and set
  the Microsoft Entra administrator.
- If the source uses a CMK, ensure the signed-in identity can grant the target
  server access to the source Key Vault and register that key with Azure SQL.
  The script supports both Key Vault access policies and Azure RBAC.
- Choose an available, globally unique Azure SQL logical server name. Use the
  same name as `-TargetServer` throughout deployment, verification, and cleanup.

## Deploy

Preview the exact deployment. This command reads configuration and Azure state
but changes nothing:

```powershell
./ha-resiliency/geo/deploy-geo-replica.ps1 `
  -TargetServer '<unique-server-name>'
```

Confirm the subscription, source, target, signed-in Entra administrator,
service objective, target HA replica count of zero, disabled target zone
redundancy, and backup redundancy. Also confirm the detected source TDE
protector. A service-managed protector reports that no CMK prerequisite is
required. A customer-managed protector reports the existing key and whether
its Key Vault uses access policies or Azure RBAC. The script creates the target
server with a system-assigned identity at server creation time; the portal
geo-replica experience does not offer that prerequisite and otherwise fails
with “The server identity is not correctly configured.”

After explicit approval, run the same deployment with `-Execute`:

```powershell
./ha-resiliency/geo/deploy-geo-replica.ps1 `
  -TargetServer '<unique-server-name>' `
  -Execute
```

The script creates:

- The reader-named logical server in `eastus2`, the paired region for the
  Central US source used by this example.
- A system-assigned identity on that server.
- Microsoft Entra-only authentication, with the signed-in Azure CLI user as
  the server administrator.
- For a CMK-protected source only, `Get`, `WrapKey`, and `UnwrapKey` access for
  the target server identity and registration of the existing source protector
  key on the target server. An RBAC-enabled vault uses the **Key Vault Crypto
  Service Encryption User** role; an access-policy vault uses the equivalent
  three key permissions.
- A `wardgeneral` Hyperscale geo-secondary that matches the source service
  objective and backup redundancy but has no HA replicas and is not zone
  redundant.

The lower-cost target still protects against loss of the Central US region
because its page servers and compute are in East US 2. It does not have a hot
local HA standby or availability-zone distribution in East US 2. If its
compute fails, Azure must create replacement compute before the geo-secondary
is available again, so local recovery can take longer.

Geo-replica creation is asynchronous. Wait until Azure reports the database
online, then verify it:

```powershell
./ha-resiliency/geo/verify-geo-replica.ps1 `
  -TargetServer '<unique-server-name>'
```

Require `GeoReplicaVerification=PASS`. The geo-secondary is read-only until a
geo-failover promotes it. Replication is asynchronous with respect to commit,
so the primary does not wait for the geo-secondary before acknowledging a
transaction.

## Clean Up

Preview cleanup only after geo-replication testing is complete:

```powershell
./ha-resiliency/geo/cleanup-geo-replica.ps1 `
  -TargetServer '<unique-server-name>'
```

The preview identifies the source that will be retained, the replication link,
the geo-secondary, and the target logical server. After explicit approval:

```powershell
./ha-resiliency/geo/cleanup-geo-replica.ps1 `
  -TargetServer '<unique-server-name>' `
  -Execute
```

Cleanup removes the replication link and deletes the named target server,
including its secondary database. It refuses to delete a server that lacks
the Ward General sandbox ownership tags or contains another database. It never
deletes or modifies the source logical server or source `wardgeneral` database.

## Boundaries

- Deployment and cleanup preview by default and require explicit approval
  before `-Execute`.
- The target server and geo-secondary are billable resources.
- The workflow is fixed to East US 2. Existing targets must carry the Ward
  General sandbox ownership tags; cleanup also refuses a server containing an
  unexpected database.
- The source server and database come from `wardgeneral.env`; no server name, password,
  or connection string is embedded in these scripts.
- The workflow detects the source server-level TDE protector. It neither
  enables CMK for readers who skipped that Security option nor replaces,
  rotates, or removes a source CMK.
- The target deliberately uses zero HA replicas and no zone redundancy to keep
  this DR example's compute cost lower. It does not match the source's local
  availability topology.
- This creates standalone active geo-replication, not a failover group.

References:

- [Microsoft Learn — Configure active geo-replication](https://learn.microsoft.com/azure/azure-sql/database/active-geo-replication-configure-portal), accessed 2026-09-08.
- [Microsoft Learn — Hyperscale secondary replicas](https://learn.microsoft.com/azure/azure-sql/database/service-tier-hyperscale-replicas#geo-replica), accessed 2026-09-08.
- [Microsoft Learn — Microsoft Entra service principals with Azure SQL](https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-service-principal), accessed 2026-09-08.
