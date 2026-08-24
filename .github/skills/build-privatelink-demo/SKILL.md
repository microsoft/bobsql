---
name: build-privatelink-demo
description: >-
  Provision, rename, re-region, verify or tear down the Azure environment for
  DATACON 2026 Demo 3 — "the control plane is the security perimeter" (Private
  Link + Entra-only Azure SQL Hyperscale + a client VM whose managed identity is
  the server admin). USE WHEN the presenter says any of: "build the private link
  demo", "provision demo 3", "set up the control plane demo", "deploy the
  privatelink demo on this machine", "rebuild demo 3", "move demo 3 to another
  region", "rename the demo 3 server", "the VM got deallocated, redeploy it",
  "run pre-flight for demo 3", "why is 05-verify failing", "tear down demo 3", or
  moves this talk to a new laptop and needs the VNet + VM + Entra-only server +
  demo kit in place. Scope is PROVISION + CONFIGURE + VERIFY + TEARDOWN ONLY. Do
  NOT use to present or rehearse the five beats (that's run-privatelink-demo), to
  build the Adventure Works / SQL MCP kit, or to deploy the Ward General
  hyperscale talk — those are separate.
---

# Build the Private Link (Demo 3) environment

Read **`presentations/dataconus2026/whyazurebest/demos/demo3_controlplane/README.md`**
first, every time. It is the source of truth and it is current. This skill covers
only what the README does not: the order to work in and the traps that have
already cost a rebuild.

All paths are workspace-relative to the **bwsql** root. Kit:
`presentations/dataconus2026/whyazurebest/demos/demo3_controlplane/`.

## The shape of it

- **Control plane runs on the laptop, `az` only.** The laptop never opens a SQL
  connection — it cannot, by design.
- **Data plane runs inside the VM, `sqlsim` only.** The VM never runs `az`.
- `az vm run-command invoke` bridges the two through ARM. It keeps working even
  after `publicNetworkAccess=Disabled`, so it is also the way back in if RDP breaks.

## Running the scripts

- **Always synchronous**, `isBackground: false`, `timeout: 0`. Provisioning steps
  run minutes. Never background them, never poll.
- **Check the exit code.** `05-verify.ps1` exits 1 when the demo is not at Beat 1.
- Every step is idempotent. If step 4 fails, fix it and run `.\setup-all.ps1 -From 4`.
- If the terminal starts mangling chained commands, switch to `execution_subagent`.

## First build on a new machine

```powershell
cd presentations/dataconus2026/whyazurebest/demos/demo3_controlplane
.\setup-all.ps1
```

Steps 1–6: network → VM → RDP rule → Entra-only server + Hyperscale DB → ODBC
prerequisites → pre-flight.

Two things need a human:

1. **Step 2 prompts for the VM local administrator password.** The presenter types
   it straight into the terminal. **Never** collect it with a question tool, never
   echo it, never put it in a script or a variable you print.
2. **`sqlsim.exe` must be dragged over RDP** into `C:\demo` — too big for
   `run-command`. `setup-all.ps1` pauses and prints the exact source path. Push the
   other three files first with `.\push-vmkit.ps1`, then finish with
   `.\setup-all.ps1 -From 6`.

Done when `05-verify.ps1` prints **17/17 PASS** and "Demo is in its Beat 1 state".

## Renaming or moving to another region

Both are edits to `00-config.ps1` — **and to `vmkit/config.ps1`**.

`push-vmkit.ps1` copies `vmkit/config.ps1` **verbatim**; it is not generated from
`00-config.ps1`. The FQDN and database name are therefore written down twice and
nothing enforces that they match.

**This has already broken the demo once.** After a re-region the VM-side file still
named the deleted server. Every laptop script and all 17 checks passed while
`query.ps1` on the VM pointed at a server that no longer existed.

Order of work:

1. Validate the target region has capacity for `Standard_E2s_v5` before touching
   anything — `az vm list-skus --location <region> --size Standard_E2s_v5` and check
   `restrictions` is empty, plus vCPU quota for the ESv5 family.
2. Edit `00-config.ps1` (`$Location`, `$ServerName`, `$DatabaseName`).
3. Edit `vmkit/config.ps1` to match.
4. `.\99-teardown.ps1 -Confirm`, then `.\setup-all.ps1`.
5. `.\push-vmkit.ps1`, then **verify by side effect**:
   ```powershell
   . .\00-config.ps1
   Invoke-VmScript "Get-Content 'C:\demo\config.ps1' | Select-String 'ServerFqdn|DatabaseName'"
   ```

Logical server names are globally unique DNS labels — a rename can collide.

## Traps that are already settled — do not rediscover them

| Trap | The rule |
| --- | --- |
| `--external-admin-sid` for a managed identity | **Application (client) ID**, never the object ID. The object ID creates cleanly and then every login fails. Never write an appId→objectId fallback |
| Entra admin assignment | Must happen at **server create time**. `az sql server ad-admin create` has no `--principal-type`, so it cannot declare `Application` |
| ODBC Driver 18 returns 1603 | Install **VC++ redist first**. The MSI log says `Error 1723`. Never diagnose an MSI from its exit code |
| `az ... dns-zone-group show` on a missing group | Returns **exit 0 and `{}`**. `Invoke-Az` maps a property-less object to `$null` — keep that fix. Verify existence checks by side effect, not by the message |
| `az vm run-command --scripts` with a multi-line string | Silently emits nothing. Use `Invoke-VmScript`, which writes a temp `.ps1` and passes `@file` |
| `Read-Host` in an agent-driven terminal | Returns empty. `99-teardown.ps1` asks for the database name, so it aborts with exit 1 and deletes nothing. The presenter must run teardown themselves |

## Teardown

```powershell
.\99-teardown.ps1 -Confirm
```

Scoped on purpose: VM, NIC, disk, public IP, private endpoint, DNS zone and link,
logical server, database, VNet, `nsg-demo3-client`, `demo3.rdp`. It **never deletes
the resource group** — `bwsqlestaterg` is shared and Demo 1 counts resources in it.
Tearing down drops Demo 1's estate by one logical server and one database, so
re-check that workbook if the recording matters.

Azure policy injects `NRMS-*` NSGs alongside the VNet. Teardown does not remove
them and they survive as orphans (`subnets: null`, `networkInterfaces: null`).
They are harmless. Confirm they are unassociated before proposing deletion, and
ask first — the resource group is shared.

## Before you change shared state

Provisioning is fine to do. Do **not**, without asking:

- re-run a beat script that locks the server down, or leave
  `publicNetworkAccess=Disabled` behind after an investigation
- delete anything in `bwsqlestaterg` that this kit did not create
- re-measure by mutating the live environment when the presenter is rehearsing

Leave the environment at **Beat 1, 17/17 PASS**.
