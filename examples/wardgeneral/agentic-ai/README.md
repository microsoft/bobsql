# Agentic AI — Build the agentic Ward General workflow

Agentic AI evolves the Ward General application from Ward General App. It does not
create a second application.

## Where the application source lives

The cumulative Ward General solution remains in
[`first-app`](../first-app/). Agentic AI adds the
[`WardGeneral.Agent`](../first-app/src/WardGeneral.Agent/) project and its
shift-handoff skill to that shared source tree. Keeping one application avoids
copying the Ward General App web and data projects into each later area and lets the
`AiAgent` feature flag expose the Agentic AI behavior without creating a separate
build.

This [`agentic-ai`](./) folder owns the Agentic AI-specific SQL,
DAB/MCP configuration, deployment and run scripts, and reader documentation. In
short: application source is under `first-app`; Agentic AI contracts and
orchestration are here.

The completed workflow is a **shift handoff**, in two turns:

> Show me the current patients that may need a shift handoff.

The agent returns at most three patients, each with the evidence behind it and a
link to that patient's chart. Then:

> Prepare patient X for shift handoff.

The agent reads that patient's chart, composes a structured SBAR handoff from it,
shows it, and proposes to save it. The framework holds that write and the
clinician approves or declines. Approving writes exactly one row to
`clinical.AgentRecommendation`.

Two turns, because that is the shape of the work: a roster question and a
document-preparation question are different tasks, and an agent that answers both
at once has decided something the clinician did not ask it to decide.

The dock carries you between them. After a roster reply the suggestion chips
become one per patient the reply named, so the second turn is a click rather than
retyping an encounter id. Those chips are built from the ids the application
parsed out of the reply, the same ids behind the chart links — the model does not
get to author the button that calls it back. Once a handoff is saved the chips
return to the roster question instead of offering the same patient again.

All patient data in this example is synthetic.

## Why this is an agent and not a chatbot

The second turn is the one that earns the word. The agent has to carry the
encounter id from its own previous reply, choose which tools to call and in what
order, compose four prose sections from what came back, and then stop short of
the write and hand the decision to a human. Nothing in that sequence is scripted
by the application. The model chooses it, turn by turn, from a typed toolbox —
including choosing what *not* to reach for.

The first turn earns it differently. `get_handoff_candidates` returns *evidence*,
not a ranking — latest vitals against the earlier reading in the same window,
medications started this shift, pending labs and how long they have been
outstanding. Deciding which of those signals matters, for these particular
patients, on this particular evening, is the judgment call. The database does the
set-based work; the model does the reasoning; neither does the other's job.

## What the reader can see

The assistant dock has a collapsible **What the agent did** panel under the
transcript. It lists every tool the model called, the arguments it chose, elapsed
milliseconds, and result size — failures included. This is the area's
observability answer: the reader watches the control loop rather than taking the
answer on faith. A production clinical app would not show this to a nurse, and
that is fine; it exists so the mechanism is inspectable while it is being taught.

For the message-level view behind that trace, see
[`payload.md`](payload.md). It follows the same handoff conversation through the
system and user messages, advertised tool definitions, `load_skill` result,
MCP `tools/call` requests, returned SQL evidence, and approval response. Its JSON
is a normalized teaching representation rather than a captured provider-specific
HTTP trace.

For a cross-area map from every database object through Agentic AI to the
application, SQL, or MCP surface that uses it, see
[`OBJECT-CATALOG.md`](OBJECT-CATALOG.md). It also calls out objects that are
deliberately present without an application caller.

## What exists now

- the application-hosted Microsoft Agent Framework client, connecting to one MCP
  endpoint and marking `save_handoff` approval-required;
- the runtime MAF Agent Skill for the handoff workflow
  ([`skills/shift-handoff/SKILL.md`](../first-app/src/WardGeneral.Agent/skills/shift-handoff/SKILL.md));
- the tool-call trace panel in the assistant dock
  ([`AgentTrace.cs`](../first-app/src/WardGeneral.Agent/AgentTrace.cs),
  [`TracedAIFunction.cs`](../first-app/src/WardGeneral.Agent/TracedAIFunction.cs));
- chart links in the dock, built by the application from the encounter ids the
  reply cited — never from a URL the model wrote;
- follow-up suggestion chips built from those same parsed ids, so a roster reply
  offers the second turn for each patient it named
  ([`AssistantDock.razor`](../first-app/src/WardGeneral.Web/Components/Layout/AssistantDock.razor));
- `clinical.GetHandoffCandidates`, the one set-based query behind the roster
  ([`12-handoff-candidates.sql`](12-handoff-candidates.sql));
- `clinical.AgentRecommendation` and `clinical.SaveShiftHandoff`, with
  request-key uniqueness ([`11-handoff-contract.sql`](11-handoff-contract.sql));
- the approval gate and its UI round trip;
- the `AiAgent` feature flag.

### What Agentic AI deliberately does not build

**There is no ordering system, and no ordering surface in the application.** The
assistant prepares a handoff and stops. If imaging looks warranted, that belongs
in the handoff's Recommendation section, and the clinician acts from the chart
where Ward General App already put them. There is no orders page, no worklist, no status
transitions, no cancellation, no radiology results.

**The database plumbing for orders is real, and it is deliberately unreachable.**
[`14-imaging-order-contract.sql`](14-imaging-order-contract.sql) deploys a
complete write path — an idempotency key, a filtered unique index, and
`clinical.PlaceImagingOrder`. Nothing calls it. There is no DAB entity, no MCP
tool, and no application code that reaches it, so the agent cannot invoke it no
matter what it is asked. Run every demo in this area and that procedure
executes zero times.

That gap is the area's point. A capability existing in the database and an
agent being permitted to invoke it are two separate decisions, made in two
separate places. The tool inventory is the hard boundary: `save_handoff` is on
the other side of it and `place_order` is not. Approval then governs the write
that *is* offered.

The two writes are also different in kind, which is why only one is exposed.
`save_handoff` records a **document about** care. `place_order` would issue an
**instruction to deliver** care. Same approval mechanism, categorically
different consequence.

## What Agentic AI changes in the Ward General App application

Agentic AI is an evolution of one cumulative app, so it is worth being precise
about what it touches. Every change is additive and inert while `AiAgent` is off.

**A new project, `src/WardGeneral.Agent/`** — the whole agent lives here, so
Ward General App's web and data projects are almost untouched:

| file | what it is |
|---|---|
| `WardGeneralAgent.cs` | the MAF client: connects to MCP, wraps tools, runs the turn, handles the approval round trip |
| `AgentOptions.cs` | endpoint, deployment, MCP url, skill path, which tools require approval, and the always-on instructions |
| `AgentTrace.cs` | the per-conversation record of tool calls behind the **What the agent did** panel |
| `TracedAIFunction.cs` | the `DelegatingAIFunction` wrapper that captures each call |
| `skills/shift-handoff/SKILL.md` | the runtime Agent Skill — the workflow the model loads on demand |

**In `src/WardGeneral.Web/`** — three small hooks and one new component:

- `Program.cs` binds `AgentOptions` and registers `WardGeneralAgent` as a
  singleton;
- `Options/FeatureFlags.cs` gains `AiAgent`;
- `appsettings.json` gains the `Agent` section, shipped with an empty endpoint;
- `Components/Layout/AssistantDock.razor` is the dock itself — transcript,
  approval card, and trace panel.

Nothing is eagerly constructed. `WardGeneralAgent` is a lazy singleton resolved
only by the dock, and the dock renders only under `@if (Features.Value.AiAgent)`.
With the flag off, no agent is built, no MCP connection is opened, and no skill
is loaded — which is what lets you drop back to Ward General App without deleting code.

**In `src/WardGeneral.Data/` — nothing.** `ChartRepository`, `AccessContext`,
`RlsOptions`, and the connection factory are exactly as Ward General App and AI-Ready SQL
left them. The agent does not go through the data-access layer; it goes through
MCP.

**`Components/Pages/Home.razor` — nothing.** This is deliberate, and the next
section explains why.

## Identity: why the system signs the handoff

Agentic AI has no authentication. Anyone who can reach the application can use it,
and every patient is reachable, because the row filtering that changes it is
Security's. That is the honest state of the app at this point in the project.

But `clinical.AgentRecommendation.ProposedById` is `NOT NULL` with a foreign key
to `ops.Provider`, because a clinical handoff with no author is not a handoff. So
the write needs an identity even though no human has supplied one.

Agentic AI resolves that with a **system provider row**, seeded idempotently by
[`11-handoff-contract.sql`](11-handoff-contract.sql):

```sql
INSERT INTO ops.Provider (FullName, DepartmentId, Role, EntraObjectId)
SELECT N'Ward General Assistant (system)', MIN(d.DepartmentId), N'System', NULL
FROM ops.Department AS d;
```

`clinical.SaveShiftHandoff` resolves that row internally. Provider identity is
not an MCP argument, does not appear in the model prompt, and is not accepted
from the application. What lands in the table is true: the Agentic AI system
proposed the handoff during an unauthenticated session. Naming a real clinician
would forge authorship, and a nullable column would let the record claim nothing
at all.

The row is seeded by the Agentic AI script rather than Getting Started's, so Getting Started's
seed and its published row counts are unchanged. It holds no patients and carries
no `EntraObjectId`, so Security's predicate matches nothing for it, and the
"Viewing as" list — which loads attendings with active patients — never shows it.

### The Security boundary

Agentic AI does not preview authentication by passing an untrusted provider id
through the model. It runs DAB under one application identity and allows every
synthetic patient to be read. Approval controls whether a proposed clinical
write executes; it does not authenticate a clinician or authorize a row.

Security owns the replacement architecture: Entra authentication, trusted
identity-to-provider mapping, DAB's session-context integration, and Row-Level
Security. That is more than changing one argument, and Agentic AI does not claim
otherwise.

### What this means when you run it

You do **not** need to pick a provider, and you do not need Security's
`RowLevelSecurity` flag to save a handoff. Run with `AiAgent` alone and the write
works. The "Viewing as" selector stays exactly where Security wants it —
[Home.razor](../first-app/src/WardGeneral.Web/Components/Pages/Home.razor)
renders it only under `RowLevelSecurity`, so a Ward General App or Agentic AI reader
never sees a control that filters nothing.

Turning on Security's `RowLevelSecurity` flag is outside this workflow. Area
6 neither requires nor simulates a clinician selection.

## One cumulative application

Application source remains here:

```text
first-app/
```

Agentic AI assets remain here:

```text
agentic-ai/
```

The Agentic AI folder owns SQL procedures, DAB configuration, probes, and
orchestration. It must not contain a forked copy of the Ward General solution.

## Prerequisites

Complete Areas 2 through 5 first. In particular, the reader needs:

- the `wardgeneral` Hyperscale database and Getting Started schema and data;
- the Ward General App application configured through its existing environment file;
- the AI-Ready SQL AI resources and database objects, including the note embeddings
  and the vector index;
- a **chat** model deployment on that same Foundry resource for the agent to
  reason with — AI-Ready SQL only needed the embeddings deployment;
- .NET 10 and the DAB CLI, **version 2.0.0 or later**.
- **go-sqlcmd** (`sqlcmd` v1.x) if you want `setup-dab.ps1` to deploy the SQL for
  you. Running the scripts yourself in the MSSQL extension or SSMS is equally
  fine — every file carries its own `SET`-options preamble.

### What Agentic AI calls but does not deploy

Areas 4 and 5 are prerequisites, not suggestions, and one tool depends on them
directly. `search_clinical_context` calls `clinical.SearchSimilarNotes`, which is
**AI-Ready SQL's** `09-research-vector-search.sql`. Agentic AI does not re-deploy it.

That is deliberate. The procedure is useless on its own: it embeds its query
through the external model created by `06-ai-embeddings.sql` and searches the
vector index built by `07-vector-index.sql`. Re-running `09` from here would
refresh one link of a four-link chain and protect nothing — while quietly
overwriting a AI-Ready SQL object from a Agentic AI script.

If you skipped AI-Ready SQL, the other six tools still work.
`search_clinical_context` fails at call time with *"Could not find stored
procedure 'clinical.SearchSimilarNotes'"*, which names the real cause.

**"Prerequisite" means state, not a step you repeat per machine.** Everything
Areas 2, 4 and 5 build lives in two shared places — the `wardgeneral`
database and your Azure resources — so it is already there when you sit down at a
second computer, and none of it needs running again. What does *not* travel is
purely local:

| Travels (do once) | Does not travel (per machine) |
|---|---|
| Schema, seed data, procedures, external model, embeddings, vector index | `wardgeneral.env` and `appsettings.Development.json` — both git-ignored |
| Foundry resource and model deployments | The built application (`build.ps1`) |
| | The trusted HTTPS dev certificate |
| | A SQL firewall rule for that machine's egress IP |

So on a fresh clone you recreate two config files, build, and go — you do not
re-run AI-Ready SQL's SQL. If you are unsure what is already deployed, ask the
database rather than guessing:

```sql
SELECT CASE WHEN OBJECT_ID('clinical.SearchSimilarNotes','P') IS NULL
            THEN 'MISSING - run AI-Ready SQL' ELSE 'present' END;
```

### go-sqlcmd, not the ODBC sqlcmd

`setup-dab.ps1` deploys three SQL scripts with `sqlcmd -G`. That flag means two
different things depending on which `sqlcmd` you have, which is why the script
checks rather than trusting the name:

| Build | What bare `-G` does |
|---|---|
| **go-sqlcmd** (v1.x) | Uses `DefaultAzureCredential` — the same passwordless identity the app and DAB already use |
| **ODBC sqlcmd** | Attempts Entra *interactive* auth, and needs ODBC 17.2 or later |

Both install as `sqlcmd`, and on Windows the ODBC build lands on the **machine**
PATH, which is searched before the user PATH. So the newer tool can be installed
and still lose. `setup-dab.ps1` resolves in this order, and skips any candidate
whose `--version` fails — a check that succeeds only on go-sqlcmd:

| Order | Location |
|---|---|
| 1 | `-SqlCmd <path>` on the command line |
| 2 | `SQLCMD` environment variable |
| 3 | `%LOCALAPPDATA%\Programs\sqlcmd\sqlcmd.exe` |
| 4 | `C:\Program Files\sqlcmd\sqlcmd.exe` |
| 5 | `sqlcmd` on `PATH` |

If none resolve, **`setup-dab.ps1` fails** — it does not skip the deploy. A
skipped deploy is the worst outcome available here: setup reports success, none
of the Agentic AI contracts exist, and the fault resurfaces later as an agent
whose tools are missing, which looks like a model problem rather than a setup
one. To run the scripts yourself instead, say so with `-SkipSql`.

```powershell
winget install --id Microsoft.Sqlcmd

# no admin? unzip a release and point at it
[Environment]::SetEnvironmentVariable('SQLCMD', "$env:LOCALAPPDATA\Programs\sqlcmd\sqlcmd.exe", 'User')
```

### The DAB version is not a detail

`runtime.mcp`, and the `dml-tools` switch inside it, do not exist before DAB 2.0
— and `dml-tools: false` is the single line that bounds the agent's tool surface
to the seven entities in this configuration. On a 1.x CLI the config still passes
schema validation, then the engine refuses to start with:

```text
Audience and Issuer must be set when using a JWT identity Provider.
```

against a configuration whose authentication provider plainly reads
`Unauthenticated`. The message points nowhere near the real cause, so both
`setup-dab.ps1` and `run-dab.ps1` check the version and say so directly. To fix
it by hand:

```powershell
dotnet tool update --global Microsoft.DataApiBuilder
dab --version    # expect 2.0.0 or later
```

The `wardgeneral-research` named replica is a AI-Ready SQL prerequisite, not a
Agentic AI one. Agentic AI does not connect to it.

`run-dab.ps1` and `setup-dab.ps1` read `WardGeneral__Server` from
`first-app/wardgeneral.env` and accept `-Server`. Neither has a built-in
server name; both stop rather than guess one.

## Configure — two files, and neither one travels

Agentic AI needs one setting Areas 4 and 5 never did: **an endpoint for the
chat model the agent reasons with**. AI-Ready SQL called its model from inside the
engine, so the application never needed to know where it lived. The Agentic AI
agent runs in the application, which means the application has to be told.

Both configuration files are git-ignored. That is deliberate — your server name
never reaches a commit, and a `git pull` can never collide with your edits — but
it has a consequence worth knowing before it surprises you: **a fresh clone, or a
second machine, has neither file.** Nothing is broken. Create them again.

**1. The database, in `first-app/wardgeneral.env`.** Running
`./first-app/load-env.ps1` creates this from the template and stops
so you can fill it in:

```ini
WardGeneral__Server=<your-sql-server>.database.windows.net
WardGeneral__Database=wardgeneral
```

This one wants the FQDN, because it goes into a connection string rather than an
`az` command. A value still in `<angle brackets>` counts as unfilled and the
scripts stop rather than run against the wrong server.

**2. The model, in
`first-app/src/WardGeneral.Web/appsettings.Development.json`.**
`appsettings.json` ships `Agent:Endpoint` empty on purpose — a default resource
name is always somebody else's environment. Create the Development file
alongside it:

```json
{
  "Agent": {
    "Endpoint": "https://<your-foundry>.openai.azure.com/",
    "Deployment": "gpt-5",
    "McpUrl": "http://localhost:5000/mcp"
  }
}
```

Use the same Foundry resource AI-Ready SQL deployed, and a **reasoning** chat
deployment on it — the handoff asks the model to weigh several signals against
each other, which is not a completion task. `McpUrl` already points at 5000 in
`appsettings.json`; repeat it here only if you moved the port.

There is no key in either file. The application authenticates to both SQL and
the model endpoint as *you*, through `DefaultAzureCredential`, so your identity
needs a Foundry data-plane role such as **Cognitive Services OpenAI User** on
that resource. An endpoint that resolves but returns 401 is nearly always a
missing role assignment rather than a wrong URL.

If you would rather not create the Development file, `Agent__Endpoint` as an
environment variable works too — environment variables outrank both JSON files.

## Target architecture

One DAB configuration carries exactly one connection string, so one DAB process
reaches one database. Agentic AI uses one, over the primary.

```text
Ward General application-hosted MAF agent
  |
  +-- MCP endpoint  (localhost:5000, connection: wardgeneral)
        reads   get_patient_chart, get_patient_chart_by_bed,
                search_encounters, get_handoff_candidates,
                search_clinical_context, clinical_assistance
        writes  save_handoff      [approval-gated]
```

The AI-Ready SQL Research page is a separate path entirely. It opens its own
ADO.NET connection to the `wardgeneral-research` named replica through
[`WardGeneralConnectionFactory.CreateResearch()`](../first-app/src/WardGeneral.Data/WardGeneralConnectionFactory.cs),
tagged `ApplicationName=wardgeneral-research` so you can see it in
`sys.dm_exec_sessions`. Agentic AI changed nothing about it.

The runtime Agent Skill tells the model how to perform the handoff workflow. It
does not enforce authorization, approval, or idempotency — those live in the
application, the framework, and the database.

## The ordering plumbing — what exposing it would take

This section is a thought experiment. Nothing in it is built, and none of it is
required to run Agentic AI. The point is to show how short the distance is
between a procedure sitting unused in the database and an agent that can act on
the world — and how deliberate each step across that distance has to be.

`clinical.PlaceImagingOrder` is already deployed by
[`14-imaging-order-contract.sql`](14-imaging-order-contract.sql). Three things
stand between it and the model.

**1. A DAB entity.** The MCP endpoint publishes what the configuration names and
nothing else, so the procedure would need an eighth entry in
[`dab-config.primary.json`](dab-config.primary.json) alongside the seven that
exist:

```jsonc
"place_order": {
  "description": "Place an imaging order for the encounter under review. ...",
  "source": {
    "type": "stored-procedure",
    "object": "clinical.PlaceImagingOrder",
    "parameters": {
      "EncounterId": 0, "Modality": "", "BodySite": "",
      "OrderedById": 0, "RequestKey": ""
    }
  },
  "mcp": { "custom-tool": true },
  "permissions": [ { "role": "anonymous", "actions": [ "execute" ] } ]
}
```

The description is not documentation — the model routes on it. A vague one is a
defect with no compiler to catch it.

**2. Registration as an approval-required tool.** Adding the entity alone would
let the agent call it unattended. `AgentOptions.ApprovalRequiredToolFragments`
is what makes Microsoft Agent Framework hold the call and surface the card, the
same mechanism `save_handoff` already uses. This is the step whose omission is
silent and expensive.

**3. A runtime Agent Skill for ordering.** The handoff skill would be the wrong
home — a handoff describes a patient, an order changes their care, and merging
the two procedures would blur exactly the line the area draws. A separate
`place-order` skill would carry the clinical procedure: what evidence justifies
imaging, which modality suits which question, what to do when the indication is
ambiguous, and when to recommend in prose instead of ordering. It would load
only when the conversation is actually about imaging.

**What none of that gives you.** Even with all three in place, an inserted row
is a record of an intent. No X-ray happens. Nothing downstream is listening,
there is no worklist, no scheduling, no radiology result coming back, and no
status beyond `Ordered`. The database has recorded that someone approved a
request — which is a genuinely useful thing, and also nowhere near a working
ordering system.

**Area 11 picks up that other end**, and shows how new rows in
`clinical.ImagingOrder` could be consumed with Azure SQL change event streaming
to feed a hospital imaging system. That system is discussed there, not built
either. The seam is the interesting part: the database contract here and the
consumer there are designed independently, and neither one has to know how the
other is implemented.

## Evolution sequence

### 1. Prove the shared-app baseline

From the repository root:

```powershell
./first-app/build.ps1
```

Capture a baseline failure before changing source. Do not attribute an existing
build error to Agentic AI.

### 2. Add the runtime shift-handoff skill

Place the workflow in a file-based MAF Agent Skill and wire it through the
current .NET `AgentSkillsProvider` context-provider API. Keep the core system
instructions short and always active — the skill body is not in context until the
model has already decided to load it, so anything that must be true on turn one
belongs in the instructions instead.

The skill separates the two questions and tells the model to answer only one per
reply. For the roster it requires, per patient, the field that drove the ranking
*with its value* — "SpO2 91%, down from 96% earlier in the window", not "vitals
are concerning". A ranking a clinician cannot audit is a ranking they cannot use.

Build immediately after this application change:

```powershell
./first-app/build.ps1
```

### 3. Add the SQL contracts

The reader runs the Agentic AI SQL themselves, in numeric order so the deployed
contracts match the DAB configuration.

| script | adds |
|---|---|
| [`11-handoff-contract.sql`](11-handoff-contract.sql) | `clinical.AgentRecommendation`, the `Ward General Assistant (system)` provider row, `clinical.SaveShiftHandoff`; removes obsolete Agentic AI wrapper procedures on upgrade |
| [`12-handoff-candidates.sql`](12-handoff-candidates.sql) | `clinical.GetHandoffCandidates` |
| [`14-imaging-order-contract.sql`](14-imaging-order-contract.sql) | `clinical.ImagingOrder.RequestKey`, the filtered `UQ_Imaging_RequestKey` index, and `clinical.PlaceImagingOrder` — **deployed but never called.** No DAB entity, no MCP tool, no application caller. See *The ordering plumbing* below |
| [`13-refresh-shift-window.sql`](13-refresh-shift-window.sql) | re-anchors the demo's shift window to now; adds genuinely outstanding labs; reshapes in-window vitals so they trend. Rerunnable and cheap on a rerun — every part is absolute rather than incremental, and the vitals rewrite touches only rows whose value would change |

Run `14` before `13`. The refresh script is last on purpose because it re-anchors
the demo window to the moment it runs, so anything that writes clinical rows has
to precede it.

The request key is what makes the handoff write retry-safe. Without database-enforced
uniqueness, the workflow must not claim exactly-once behavior — an application
check alone loses the race.

Validate directly that:

- valid input inserts one row;
- invalid input inserts zero rows;
- retrying the same request key cannot insert a second row.

`12-handoff-candidates.sql` has a documented limitation worth knowing before you
read its output: `clinical.Diagnosis` carries no timestamp, so "added recently"
is approximated by identity order. The script says so rather than implying a
precision it does not have.

`13-refresh-shift-window.sql` is the one script here that is not a contract, and
it exists because of how the Getting Started seed works. The seed places each active
admission a few hours before the moment it runs — correct on the day, stale a week
later. `clinical.GetHandoffCandidates` looks back twelve hours, so on any day but
seeding day it correctly returns an empty roster, and the area's first turn has
nothing to reason about. The script shifts activity on **active** encounters
forward by the measured gap, in one transaction, and leaves discharged encounters
alone — those are the historical note corpus the Research page searches, and they
are supposed to be old.

It also fixes a subtler gap. `PendingLabCount` counts labs in `Ordered` or
`Collected` status, and every seeded lab is `Resulted`, so that column could never
be anything but zero no matter what the date was. The script creates outstanding
labs for roughly forty percent of active encounters, so the signal the tool
advertises is a signal that exists.

The third part is about vitals, and it is the one worth understanding, because
without it the area's first turn produces an answer that is well-formed and
meaningless. Getting Started generates vitals as a counter: heart rate climbs 117, 118,
119, then wraps to 100 and climbs again. `clinical.GetHandoffCandidates` reports
each vital as a pair — the latest reading and the earliest one still inside the
twelve-hour window — so on that data "up from" is an artifact of where the window
happens to start, and when the wrap falls inside the window the pair *inverts*: a
patient whose numbers never changed appears to have dramatically improved. The
agent is not wrong when it reports this. The tool is not wrong either, and neither
is the SQL. The data is what is wrong, so the data is what the script fixes.

It rewrites the readings inside the window as a line from a per-encounter
baseline, with a small jitter so no series is suspiciously smooth. Every encounter
gets one of three courses: about twenty percent **deteriorating**, twenty percent
**improving**, the rest **stable**. Values are absolute rather than incremental,
so a rerun recomputes the same line instead of compounding drift.

Two details in that assignment are deliberate. The course is keyed off
`(EncounterId / 5) % 5` while the outstanding labs use `EncounterId % 5`, so the
deteriorating patients are not the same patients who have a lab pending — two
signals that always agree would teach you nothing about weighing evidence. And a
fifth is a large share to move, but `clinical.GetHandoffCandidates` does not rank:
it returns the ten most *recently active* encounters, not the ten sickest. Shape
too few patients and the roster the model actually receives contains none of them.

The script's verification block prints one encounter per course with the earlier
and latest values for heart rate, SpO2 and temperature — the same pair the tool
reports — so a sign error shows up in the script's own output rather than inside
a model's answer.

Rerun it whenever the roster comes back empty, or whenever the vitals stop
trending. It is idempotent: it measures the gap each time, prints
`Window already fresh` and changes nothing when there is nothing to do.

### 4. Publish the MCP endpoint

`setup-dab.ps1` installs the DAB CLI, deploys the scripts above, and validates
the config. Then:

```powershell
./agentic-ai/run-dab.ps1
```

It resolves the server from `WardGeneral__Server` or `-Server`, connects
passwordless with `Authentication=Active Directory Default`, validates the config
before starting, and sets the port through `ASPNETCORE_URLS`. Note that
`dab start` has **no** `--port` switch — the port is an ASP.NET Core host
setting.

Inspect the tool inventory before connecting the model:

```powershell
./agentic-ai/probe-mcp.ps1
```

The tool list is the agent's actual security surface: whatever is on it, the
model may call; whatever is not on it cannot be reached no matter what the prompt
says. Entities are named in literal snake_case so the emitted MCP tool name is
exactly what the area and the skill call it, independent of DAB naming
conventions. There is no generic SQL execution tool anywhere in the config.

The file declares exactly **seven entities**, and all seven become named MCP
tools. Six are ungated operations and `save_handoff` is the one approval-gated
write. Procedures the agent does not use are not declared.

Seven tools is the whole inventory, and it is seven only because
`dab-config.primary.json` sets `runtime.mcp.dml-tools` to `false`. DAB publishes
its seven generic tools **on by default**, and one of them, `execute_entity`, can
call a stored procedure by name — including the procedure the application
approval-gates. That is a path around the gate, so the area turns the generic
set off and the seven named tools become the entire surface. If the probe ever
reports more than seven, that is the setting to check first.

### 5. Add the MAF approval round trip

Mark `save_handoff` approval-required using the current Microsoft Agent Framework
mechanism. The UI must display the exact pending action — the tool name and every
argument the model proposed, verbatim.

Approval and rejection must answer that exact framework request in the same agent
session. A conversational **yes** is not an approval response. Rejecting must
execute no write. Approving must execute once and report the returned
`RecommendationId`.

The model supplies no provider identity. `clinical.SaveShiftHandoff` derives
`PatientId` from the encounter and attributes the Agentic AI handoff to the
system provider inside SQL. Security authenticates the DAB request and adds
row authorization while retaining that system attribution.

### 6. Clean build

`run.ps1` uses `dotnet run`, so restarting already compiles Agentic AI source
edits. Build explicitly anyway so compiler errors appear on their own rather than
inside startup output.

Stop the app first — Windows holds the running app's assemblies open:

```powershell
./first-app/shutdown.ps1
./first-app/build.ps1 -Clean
```

### 7. Run

For a durable local demo, use the shared application launcher. It starts and
probes DAB when `AiAgent` is enabled, then starts the app; both processes survive
terminal and VS Code closure and write logs under
`%LOCALAPPDATA%\WardGeneral\logs`:

```powershell
./first-app/start-demo.ps1 -Enable AiAgent
./first-app/start-demo.ps1 -Enable AiAssistance,AiAgent
```

Use the separate foreground commands below when debugging DAB startup:

```powershell
./agentic-ai/run-dab.ps1        # terminal 1, port 5000
./agentic-ai/probe-mcp.ps1      # terminal 2
./first-app/restart.ps1 -Enable AiAgent
```

**Coming back on a later day?** The shift window will have aged out, and the
first turn will correctly report that nobody needs a handoff. Use the wrapper
instead of the bare restart — it re-anchors the window, then starts the app:

```powershell
./agentic-ai/run-dab.ps1              # terminal 1, still required
./agentic-ai/refresh-and-run.ps1     # terminal 2
```

`refresh-and-run.ps1` runs [`13-refresh-shift-window.sql`](13-refresh-shift-window.sql)
and then hands off to `restart.ps1`. It takes the same `-Enable` list, so
`-Enable AiAssistance,AiAgent` gives the whole application; `-SkipRefresh`
restarts without touching data when the window was already refreshed today. It
deliberately does **not** start DAB — the pre-flight below already catches that
and names the script to run.

**It can stop and wait for you.** `restart.ps1` checks the server firewall rule
for this client's IP and **prompts for approval** before adding or updating it.
That is a real prompt on standard input: answer it, or pass `-SkipFirewall` when
the rule is already in place. `-SkipPreflight` passes through too. This matters
most when the script is launched somewhere the prompt is easy to miss — a
background terminal looks idle rather than blocked.

DAB must be running before the app starts with `AiAgent` on, and the app now
enforces that rather than trusting it. With the flag set, Ward General App's
`preflight-run.ps1` probes `Agent:McpUrl` and **refuses to start** when nothing
answers, naming `run-dab.ps1` in the error. An agent that launches with no tools
is the worse outcome: the dock opens, the model answers from nothing, and you
debug a prompt when the real problem is a process that was never started.

The check runs only when `AiAgent` is on, so Ward General App and AI-Ready SQL readers never
see it. It also warns when the endpoint answers with a tool count other than
seven.

Give DAB time to bind before starting the app. It acquires an Entra token and
reads schema metadata for every entity at startup, so on a slow link the first
bind can take a couple of minutes. Wait for its listening line, or for
`probe-mcp.ps1` to return, rather than assuming it failed.

The restart script prints the local application URL.

### 8. Run AI-Ready SQL and Agentic AI together

Nothing forces you to pick one area's features at a time. `-Enable` takes a
list, so one restart brings up the whole application — AI-Ready SQL's AI assistance
card and Research page alongside Agentic AI's assistant dock:

```powershell
./first-app/restart.ps1 -Enable AiAssistance,AiAgent
```

`-Enable` is the complete set of flags to force on, and it is not sticky. Naming
only `AiAgent` on the next restart turns the AI-Ready SQL surface back off, which is
the behavior that lets you return to any area's state without editing code.

Running both at once also puts the area's architecture on screen at the same
time, which is the real reason to do it. The two AI features reach the database
by different routes:

| surface | route | database |
|---|---|---|
| AI-Ready SQL — **Research** page | its own ADO.NET connection, `WardGeneralConnectionFactory.CreateResearch()` | `wardgeneral-research` named replica |
| AI-Ready SQL — **AI assistance** card | the ordinary application connection | `wardgeneral` primary |
| Agentic AI — **assistant dock** | every tool through the one MCP endpoint | `wardgeneral` primary |

The agent never reaches the named replica, and the Research page never goes
through DAB. Watch it in `sys.dm_exec_sessions` while both are running: the
research connection is tagged `ApplicationName=wardgeneral-research`, so the
vector search separates from the agent's traffic by name.

This needs both areas' database objects installed — AI-Ready SQL's `06` through
`09`, and Agentic AI's `11` through `13`. A missing AI-Ready SQL object shows up as
a failing assistance card while the agent keeps working, because the two paths
share nothing but the server.

## End-to-end proof

No provider selection and no Security flag — `AiAgent` alone is enough. The
handoff is attributed to the system provider, which is what an unauthenticated
session honestly is.

1. Ask **Show me the current patients that may need a shift handoff.**
2. Open the trace panel. Confirm `get_handoff_candidates` ran **once**. If the
   model instead called `get_patient_chart` per patient, the skill is not being
   loaded — fix that rather than accepting the answer.
3. Confirm each ranked patient carries a named field and its value.
4. Name one of them: **Prepare patient X for shift handoff.**
5. Confirm the trace shows `get_patient_chart` for that encounter, and that
   `search_clinical_context` was **not** called — a handoff is built from this
   patient's chart alone.
6. Confirm the four SBAR sections appear before the approval card.
7. Decline, then query `clinical.AgentRecommendation` by request key: the
   inserted-row delta must be zero.
8. Repeat with a new key, approve, and query again: the delta must be exactly
   one.
9. Approve again with the same key: the delta must still be one.

A plausible answer without the expected tool trace fails the test. An approved
conversation without exactly one durable row also fails.

## Rollback — going back to Ward General App or AI-Ready SQL

Three layers behave differently.

**The application — just drop the flag.** `-Enable` is the complete list of flags
to force on, and it is not sticky:

```powershell
./first-app/restart.ps1                        # back to Ward General App
./first-app/restart.ps1 -Enable AiAssistance   # back to AI-Ready SQL
```

The Agentic AI code is still compiled in, but none of it runs. The agent is
resolved only by the assistant dock, and the dock renders only when `AiAgent` is
on — so with the flag off there is no agent, no MCP connection, and no runtime
skill. Stop DAB too; nothing calls it now.

**The SQL — leave it.** Everything Agentic AI adds is backward compatible.
Areas 4 and 5 behave exactly as before with it installed. Remove it only for a
clean schema, in dependency order:

```sql
DROP PROCEDURE IF EXISTS clinical.GetHandoffCandidates;
DROP PROCEDURE IF EXISTS clinical.SaveShiftHandoff;
DROP TABLE     IF EXISTS clinical.AgentRecommendation;
DELETE FROM ops.Provider WHERE FullName = N'Ward General Assistant (system)';
```

Delete the system provider row *after* the recommendation table, not before —
the foreign key holds it in place while any handoff still references it.

**The data.** Handoffs are self-contained: `clinical.AgentRecommendation` holds
nothing but agent-created rows, so dropping the table removes them all and
touches no Getting Started seed data.

If you want the pre-Area-6 *source* back, that is a Git operation in your own
clone. Commit or stash your Agentic AI work first so you do not lose it.

## Agent-driven workflow

Ask Copilot to **build the Agentic AI agent**, **evolve the Ward General app**,
**set up the Agentic AI SQL MCP tools**, or **run the app with AiAgent**. The
repository skill is:

```text
.github/skills/wardgeneral-agent/SKILL.md
```

It follows this same sequence and must stop at any missing completion gate rather
than treating the chat icon as proof.

## Stop

```powershell
./first-app/shutdown.ps1
```

Then Ctrl+C the DAB terminal.
