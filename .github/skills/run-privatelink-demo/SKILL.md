---
name: run-privatelink-demo
description: >-
  Drive the live five-beat Private Link demo for DATACON 2026, "Why Azure Is the
  Best Cloud for SQL" — Demo 3, the control plane is the security perimeter
  (Entra-only Azure SQL Hyperscale, a client VM whose managed identity is the
  server admin, and the private DNS zone that nobody links). USE WHEN the
  presenter says any of: "let's run demo 3", "start the private link demo", "run
  the control plane demo", "let's do the five beats", "walk me through demo 3",
  "next beat", "rehearse the private link demo", "pre-flight demo 3", "reset the
  demo", "is demo 3 ready", "what do I say at beat 4", "the VM query still
  works, is that right", or wants step-by-step help presenting the Private Link
  arc. Scope is RUN / REHEARSE / RESET the five beats ONLY. Do NOT use to
  provision, rename or re-region the environment (that's
  build-privatelink-demo), to run the Adventure Works SQL MCP demos, or to run
  the Ward General hyperscale demos — those are separate.
---

# Run the Private Link demo (Demo 3)

Read **`presentations/dataconus2026/whyazurebest/demos/demo3_controlplane/README.md`**
first. It holds the narration, the measured findings and the Learn quotes. Drive
from it; do not invent beats.

Kit: `presentations/dataconus2026/whyazurebest/demos/demo3_controlplane/`.
This skill assumes the environment already exists.

## What the demo proves

A perimeter around a PaaS database is a **control-plane property**, not a firewall
exercise. Five `az` commands take the database from publicly addressable to
reachable only from inside the VNet — no firewall rule deleted, no VPN, no code
change, no redeploy, no new connection string.

Then it lands the most common Private Link failure in production: endpoint right,
zone right, A record right, still resolves public — because nobody linked the zone
to the VNet.

## Pre-flight — always, before the first beat

```powershell
cd presentations/dataconus2026/whyazurebest/demos/demo3_controlplane
.\reset-demo.ps1     # rewinds beats 2, 3, 5; repoints RDP at the current public IP
.\05-verify.ps1      # must print 17/17 PASS, "Demo is in its Beat 1 state"
mstsc .\demo3.rdp    # sign in as demoadmin
```

Run scripts **synchronously** (`isBackground: false`, `timeout: 0`) and check the
exit code — `05-verify.ps1` exits 1 if anything is out of place.

A new venue means a new egress IP, which breaks RDP. `reset-demo.ps1` calls
`allow-me.ps1` for you; run it standalone if only RDP is broken.

**`reset-demo.ps1` re-enables public access first, and that order is load-bearing.**
With public access disabled, any attempt to add or edit a firewall rule is denied
(Error 42101).

## Two windows, and they never swap

Laptop terminal = **control plane**. RDP session = **client**. That split is the
point. Say so at the start and keep both on screen the whole time.

## The five beats

| # | Window | Run | Expected |
| --- | --- | --- | --- |
| 1 | VM | `.\query.ps1` | Works over the public endpoint |
| 2 | Laptop | `.\beat-2-add-privatelink.ps1` | PE + zone + A record. **No VNet link** |
| 2 | VM | `.\query.ps1` | **Still works** — adding Private Link broke nothing |
| 3 | Laptop | `.\beat-3-lockdown.ps1` | `publicNetworkAccess=Disabled`, every firewall rule left in place |
| 4 | VM | `.\query.ps1 -Expect Fail` | **Blocked** — public access denied |
| 4 | VM | `.\dns.ps1` | Resolves a **public** address — the zone isn't linked |
| 5 | Laptop | `.\beat-5-dns-link.ps1` | VNet link created |
| 5 | VM | `.\dns.ps1` | Resolves **10.42.1.4** |
| 5 | VM | `.\query.ps1` | Works again, privately |

Drive **one beat at a time**: say which beat, give the command, wait for the result,
confirm it matches, then ask before moving on.

## Narration the presenter should not miss

- **Beat 1** — `query.ps1` prints `SUSER_SNAME()`, so the audience *sees* the managed
  identity connect. No password exists anywhere on this server; SQL auth was off
  from birth. The `0.0.0.0` "Allow Azure services" rule is deliberately **on** — it
  is the anti-pattern the demo exists to kill.
- **Beat 2** — the payoff is that *nothing happens*. Adding a private endpoint is
  additive and non-breaking.
- **Beat 3** — read the firewall rules on screen. Every one survives. The rule bought
  nothing; disabling public access did all the work.
- **Beat 4** — the big one. `dns.ps1` shows public DNS *already* CNAMEs the server to
  its `privatelink` name. The VM is asking for exactly the right thing; it just has
  no private zone to answer with. That is Learn's number-one cause, live.
- **Beat 4** — say this out loud: `Test-NetConnection -Port 1433` reports
  `TcpTestSucceeded : True` **even with public access disabled**. The TCP handshake to
  the gateway still completes; rejection happens at *login*. Nobody should use
  `Test-NetConnection` as proof a database is locked down.
- **"But I can still resolve the name"** — yes. Resource existence is enumerable;
  resource access is not. Beat 4 is the proof.

## Do not read numbers off the slide

The private address (`10.42.1.4`) and the topology are real and pinned. The
**public-side** addresses are deliberately not — the gateway varies by region and
round-robins between rehearsals. Read the tail of the CNAME chain off the screen.
Likewise, do not quote a specific login error number; read the message that appears.

## Recovery

| Symptom | Do this |
| --- | --- |
| Beat 5 `dns.ps1` still shows a public IP | Run it once more. The link takes seconds to propagate; `Clear-DnsClientCache` is already in the script |
| Beat 4 shows a **private** IP | The VNet link already existed — Beat 2 must not create it. Run `reset-demo.ps1`; `05-verify.ps1` fails if it finds a link |
| Beat 2 says "already exists" but the A-record list is empty | It created nothing. Verify by side effect, not by the message |
| RDP won't connect | `.\allow-me.ps1` |
| VM unreachable but ARM works | `Invoke-VmScript` from `00-config.ps1` goes through ARM, not the VNet |
| VM query fails against a server that doesn't exist | `vmkit/config.ps1` drifted from `00-config.ps1`. Fix both, `.\push-vmkit.ps1` |

Edited anything under `vmkit/`? **Re-push it.** The VM runs its own copy in `C:\demo`.

## Between rehearsals, and when you finish

```powershell
.\reset-demo.ps1
.\05-verify.ps1
```

Always leave the environment at **Beat 1, 17/17 PASS**. Never walk away with
`publicNetworkAccess=Disabled` still set — the next pre-flight will fail with
Error 42101 before it can fix itself.

Deallocate the VM between rehearsals. Serverless Hyperscale bills per second and
does **not** auto-pause; that's General Purpose only.
