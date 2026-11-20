# SQL Migration Studio

A separate, local Azure-themed migration application: React + Fluent UI, an
ASP.NET Core host, GitHub Copilot SDK, adapted public skills, and fixed migration
operations. The existing Service Desk and its container are not replaced.

## Architecture

```text
Standalone Edge window
    | same-origin protected API + event stream
    v
Local .NET host (127.0.0.1:5188)
    |-- Copilot SDK: adapted skills and read-only guidance tools
    |-- Approval and immutable run state
    `-- Fixed PowerShell operations -> Docker / Azure CLI / SqlPackage
```

Copilot reads real adapted skill instructions, answers operator questions, and
inspects sanitized readiness and execution status. The host executes the actual
migration after a separate wizard approval. The model cannot invoke arbitrary
shell commands, edit files, read credentials, or approve Azure operations.
This is an agent-assisted, host-executed workflow, not an unrestricted agent.

The migration wizard stays in the center. The right-hand Copilot pane defaults
to **Agent flow**, showing the skill catalog, per-skill read states, and a
timestamped, filterable debug console; **Chat** is a separate tab. On narrow
screens the agent pane stacks below the wizard. Session
availability is separate from actual `read_skill_instructions` calls. Tool
and skill reads emit started/completed/failed events from the host callbacks;
they never imply that provisioning or migration ran. The trace omits prompts,
arguments, results, and credentials. It uses the shared 500-event replay buffer,
not a permanent audit log, and does not expose private model reasoning.
The right pane contains **only Copilot activity**, never app discovery or migration
operations. Those remain in the center's expandable Technical activity log.
**Start Copilot guide** opts into real agent requests: once per visited step,
Copilot is asked to read the relevant adapted skill and call its read-only
readiness/status tools. Only public step and skill names are submitted; selections
and account identifiers are not sent. Each request uses Copilot usage. No request
is submitted before opt-in and authenticated SDK readiness. Stopping the guide
stops future requests, not an already active response. Failed requests are not
silently retried; actual events, not the prompt, establish which tools ran.
The pane explicitly reports missing Copilot sign-in. Azure sign-in is separate.

## Build and run

Prerequisites: .NET 10 SDK, Node.js/npm, PowerShell 7.4+, Docker Desktop, Azure CLI,
and compatible SqlPackage. Additional operation prerequisites are reported by
preflight; missing tools do not cause automatic installation or paid fallback.

```powershell
# From the migration-studio folder:
.\build.ps1
.\run.ps1
```

The launcher opens an actual standalone Microsoft Edge app window. Use
`run.ps1 -NoBrowser` when restarting without another window. No database or Azure
deployment occurs merely by starting the app. A separate local runtime serves
the Service Desk on port 5187; the Studio launcher never stops it.

Copilot and Azure use separate sign-ins. Copilot readiness checks authentication
and available models without submitting an inference request. Sending a chat
message uses the selected account's Copilot allowance; it is not guaranteed free.
Use **Connect Copilot** in the right pane if authentication is blocked. Copy the
one-time code, open the GitHub verification link, and authorize your account.
The SDK handles authorization; no access token is collected by or returned to the
browser. Only the requesting local browser session can see its code or cancel
its attempt. The host waits once on the SDK while the UI reads progress; refreshing
or hiding the pane does not start another authorization attempt. Codes expire,
and failures/cancellation are explicit. Additional account selection or plaintext
credential-storage consent is not automatically approved.
An intermediate SDK `awaiting` step is advanced until a terminal result or code
expiry, not treated as failure. Consent, account-selection, declined, and error
responses are reported separately without exposing raw authorization diagnostics.
If the SDK requires consent or account selection, repeating GitHub authorization
alone is not a remedy; that follow-up remains blocked rather than auto-approved.
Connection becomes ready only after SDK authentication and model discovery succeed.
Sign-in does not send an inference request or approve any Azure operation.
The SDK uses an isolated Copilot home at
`%LOCALAPPDATA%\SqlMigrationStudio\agent`. An authenticated VS Code chat alone
does not establish this app's SDK session. The app does not copy VS Code/CLI
tokens, change Azure sign-in, or sign out other applications.
The host uses the SDK's `CopilotCli` mode only to retain access to the operating
system's secure credential store. `Empty` mode forcibly disables that store and
therefore cannot persist this device login without plaintext consent. This is a
local, single-Windows-user application, not a multitenant service: the secure
store is user-wide, while configuration stays in the protected app home.
Both sign-in and guidance sessions explicitly disable ambient discovery, custom
instructions, plugins, hooks, host Git operations, built-in agents/skills,
cross-session memory and telemetry. Sign-in has no tools; guidance allows only
the three read-only host tools and three adapted skills. A deny-by-default
permission handler remains installed. Plaintext storage is still never approved.
Never paste passwords, tokens, connection strings, SQL rows, private code, or
embedding vectors into chat.

## Workflow

1. Select the local container, click **List databases**, and select the database.
   The Source screen shows the next action inline; connection details, readiness,
   and technical activity are expandable so they do not obscure getting started.
   Source READ_ONLY is required before export, not before discovery.
2. Select tenant, subscription, region, resource group, server, and target name.
   The wizard distinguishes new resources from existing ones.
   Type part of a subscription name or ID to filter the subscription picker,
   then explicitly select a match. Typing alone does not select a destination.
   Existing logical servers supply the database region automatically. Region
   discovery is requested only when creating a server (and optionally a group).
   All subscription-scoped discovery includes both tenant and subscription IDs.
   Token acquisition uses `--subscription` only after verifying that subscription
   belongs to the selected tenant; Azure CLI rejects combining it with `--tenant`.
   Identity lookup also checks the token tenant and Graph user object ID.
3. Confirm the current Azure user for Entra administration. Existing server
   settings are never silently replaced.
4. Review the immutable configuration, free-offer protection, and offline gate.
5. Explicitly approve migration. Execution must independently establish source
   consistency and target eligibility; checking a box is not proof.
6. Observe actual export/import progress and compare target evidence.

The free-offer database must be created empty with `useFreeLimit=true` and
`AutoPause` at exhaustion. Import targets that database; it must not create a
generic paid database as a fallback. The workflow retains partial resources for
inspection on failure instead of deleting them automatically.

The first release is intentionally conservative about source consistency and
network access. A writable source or unapproved target connectivity can block
migration. The app does not force the source read-only, stop arbitrary clients,
or create broad firewall access on its own. Review the scripts' documented gate.
An app connection switch remains a separate operation and must not be presented
as completed when its UI is disabled.

## State and secrets

Run manifests, sanitized events, requests, and migration artifacts are stored
under `%LOCALAPPDATA%\SqlMigrationStudio`, protected to the current Windows user
and SYSTEM. Credentials remain in the local operation host; they are not returned
by the HTTP API or provided to Copilot. Request files are removed after execution.
Do not upload protected diagnostics or BACPACs to Git.

The application binds only IPv4 loopback, validates local Host and Origin, uses
HttpOnly SameSite session cookies and anti-forgery tokens, and denies mutating
requests without the local operator session and valid token. It is not a
multi-user hosted service and should not be reverse-proxied or exposed publicly.

SDK: pinned `GitHub.Copilot.SDK` 1.0.34 and its matching bundled runtime.
Upstream main has newer branding/API changes; do not copy incompatible examples.
Adapted skill origins and revisions are displayed in the UI and recorded in NOTICE.
Instructions were adapted from the MIT-licensed `microsoft/microsoft-sql` plugin
collection; no container image is redistributed by this application.

## Validation and evidence

Use the tests and `server\MigrationStudio.http` for local checks. The HTTP file
labels the real-inference request and uses a deliberately invalid migration
approval phrase to avoid accidental cloud execution.

Local builds, mocked failure tests, SDK authentication, live metadata discovery,
and an actual cloud migration are different levels of evidence. A successful
local build does not prove BACPAC feature fidelity or Azure free-offer eligibility.
The UI must report failed, blocked, and not-tested states explicitly.

### Local verification

- Production frontend build and .NET publish passed.
- 27 API/approval/trace/authorization/runtime tests and 12 frontend tests passed. The operation
  engine's prior 29-test validation is unchanged by the sign-in work.
- Live host, all 21 OpenAPI paths, session bootstrap, and event connection checked.
- Real SDK device-code issuance, pending-attempt reuse, per-browser challenge
  isolation, pane refresh recovery, and cancellation passed without inference.
  Browser fixtures additionally checked expiry, denial, retry, automatic connection
  updates and guide enablement. Fixtures are not evidence of completed GitHub
  authorization; that requires the operator to authorize the account on GitHub.
- The real bundled native runtime was also checked in secure-store-capable mode:
  the sign-in session had zero initialized tools and a guidance session exposed
  only its explicitly supplied read-only host tool, without inference.
- Actual source discovery returned `CustomerServiceDesk`, seven tables and
  1,001 cases. Discovery connects to each database rather than relying on
  cross-database `HAS_DBACCESS` from master, which returned NULL for this source.
- Azure tenant discovery succeeded without resource creation or account changes.
- Edge rendering checked at widths 1512, 1000, and 390 without horizontal overflow.
- Existing Service Desk health remained reachable with 1,001 cases and search ready.

Current machine blockers: a compatible SqlPackage installation was not discovered,
and the operator must complete **Connect Copilot** for the isolated SDK session.
The verification attempt was cancelled without authorizing an account.
No chat inference, source
write quiescence, BACPAC export/import, cloud provisioning, or cutover was executed.
Actual cloud feature fidelity and free-offer eligibility remain unverified.
