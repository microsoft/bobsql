# Migration Studio operations

Code-only delivery does **not** authorize cloud creation, export/import, write
quiescence, or Service Desk cutover. No installation or source alteration is
performed by these scripts.

## Backend contract

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File .\scripts\Invoke-StudioOperation.ps1 `
    -Operation Preflight -InputFile 'C:\protected\request.json'
```

`InputFile` must be a local absolute Windows path, owned by the process user and
readable/writable only by that identity and SYSTEM. Reparse points, traversal,
alternate streams, and files over 64 KiB are rejected. Keep the backend's run root
outside Git and restrict its ACL before writing requests.

Operations: `Containers`, `Databases`, `Preflight`, `Tenants`, `Subscriptions`,
`Locations`, `Groups`, `Servers`, `Identity`, `Migrate`. Discovery never provisions.
Only the approved `sqldbcontainer` may supply credentials; Docker `Config.Env` is
read in memory, never `creds.env`. SQL connections use its discovered loopback
port and a nonpooled administrator credential with UNMASK.

Every successful operation emits exactly one final JSON value (discovery arrays
remain arrays). Progress is `STUDIO_EVENT ` followed by compressed
`{stage,state,message}` JSON. Failure emits `{success:false,code,safeError}` and
exits 1. No native diagnostics, SQL rows, SQL text, passwords, tokens, or connection
strings are streamed. Backend must continue withholding stderr.

Preflight returns `{capabilities:[{name,state,detail}]}` with `ready`, `blocked`,
or `unknown` states and real tool versions in details. Successful migration returns
`verified:true` only after the actual implemented fidelity checks pass; per-feature
untested results remain explicit. Failure always returns `verified:false`.

Configuration fields:

```json
{
  "containerName": "sqldbcontainer",
  "sourceDatabase": "CustomerServiceDesk",
  "tenantId": "<GUID>",
  "subscriptionId": "<GUID>",
  "region": "<discovered-region>",
  "resourceGroup": "<selected-group>",
  "createResourceGroup": false,
  "serverName": "<selected-server>",
  "createServer": false,
  "targetDatabase": "<new-database>",
  "authentication": "Entra",
  "runDirectory": "C:\\protected\\runs\\<unique-run>",
  "confirmation": "CREATE FREE DATABASE AND MIGRATE",
  "writersStopped": true
}
```

Backend approval must bind the complete configuration and exact operations.
The confirmation string is defense in depth, **not** authentication or a substitute
for backend approval. Requests cannot supply command text, SQL, credentials,
connection strings, SKUs, firewall rules, or executable paths.

## Prerequisites and deliberate blockers

- Windows PowerShell **7+** (`pwsh`), local Docker engine, Azure CLI signed into the
  selected tenant/subscription, and the existing compatible `SqlServer` PowerShell
  module for read-only SQL checks. This mirrors `build-database.ps1`; no .NET 10 app
  DLL is loaded into an older PowerShell runtime.
- SqlPackage **170.5.96.0 or later**, including adjacent .NET DacFx assemblies.
  Supply a trusted operator environment variable `STUDIO_SQLPACKAGE_PATH` for an
  installation not on PATH. The CLI version is checked; an isolated PowerShell
  worker loads the corresponding DacFx assemblies. Export/import use DacFx APIs
  in memory, **not** secret-bearing process arguments or undocumented response
  files. Incompatible runtimes fail rather than falling back.
- The source database must **already be READ_ONLY**, established under separate
  live operational approval. `writersStopped=true` is only an acknowledgment.
  This engine never stops the app, changes database state, or restores writers.
  Read-only status, owner/UNMASK privilege, and content are checked before/after
  export. Unsupported comparison types block before provisioning.
- Existing narrow client firewall connectivity is required. **No firewall rule**
  is created and no public-IP service is contacted. A freshly created server
  therefore requires a separately approved network action before transfer.
- Only the selected tenant's confirmed Graph `/me` user may administer a new,
  Entra-only server. Existing server admin/auth settings are never changed.
  Group/service-principal administrators require a future separately reviewed
  adaptation. Azure commands always specify subscription; never `az account set`.
- A new General Purpose Gen5 serverless 2-vCore database, max 32 GiB, is created
  with `useFreeLimit=true` and `freeLimitExhaustionBehavior=AutoPause`.
  Protections are rechecked before/after transfer. There is no paid fallback.
  Existing target databases are refused, including partially imported databases.
  This is more conservative than accepting an unrelated empty database.

Preflight reports tool readiness, not a feature-fidelity or Copilot-auth claim.
Actual BACPAC compatibility with preview JSON/vector/regex features is established
only by an explicitly approved live migration. DacFx uses a short-lived target
token; very long imports may fail token expiry and must be inspected, not retried
automatically.

## Evidence, failure, cancellation

Unique protected run directories contain a frozen request, exclusive execution
marker, append-only sanitized event journal, BACPAC, protected DacFx working data,
and verification/failure JSON. Keep **all** run directories outside Git.
The marker is created atomically and prevents replay after a lost response.

Create `cancel.request` in the protected run directory to request cancellation.
The supervising engine kills its owned DacFx child process tree and waits for
exit before reporting cancellation. Backend process-tree cancellation is also
supported; killing a client cannot guarantee an already submitted Azure control
plane operation stops. Always re-inspect Azure resources after cancellation or
process loss. Never automatically delete resources or resume writes.

Verification compares actual per-table row counts and sorted SHA-256 row-content
hashes, including privileged contacts, textual JSON/vector representations and
embedding profiles. Identity seed, increment, and last values are preserved and
compared. Rowversion bytes are excluded because they regenerate.
Column metadata, mask functions, basic index catalog metadata, stored modules,
and explicit permissions are compared; restricted existing verifier masks,
native JSON filtering, and a real prepared vector query are executed. This is
not proof of every index option or an ANN execution plan. External runtime login,
new live embeddings, app cutover, and rollback are explicitly **not tested**.
No application configuration is changed.

## Tests

```powershell
Invoke-Pester .\tests\powershell -Output Detailed
```

Tests mock native/SQL/cloud boundaries and perform no Docker, Azure, export,
import, quiescence, or application changes.

## API references

- [SqlPackage reference](https://learn.microsoft.com/sql/tools/sqlpackage/cli-reference)
- [DacServices.ExportBacpac](https://learn.microsoft.com/dotnet/api/microsoft.sqlserver.dac.dacservices.exportbacpac)
- [DacServices.ImportBacpac](https://learn.microsoft.com/dotnet/api/microsoft.sqlserver.dac.dacservices.importbacpac)
- [IUniversalAuthProvider](https://learn.microsoft.com/dotnet/api/microsoft.sqlserver.dac.iuniversalauthprovider)
- [Azure SQL free offer](https://learn.microsoft.com/azure/azure-sql/database/free-offer)
- [Vector data type](https://learn.microsoft.com/sql/t-sql/data-types/vector-data-type)
