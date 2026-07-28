# Ward General — Deck Outline (slide-by-slide)

Working slide plan for **W25 · The Developer's Guide to Azure SQL Hyperscale**
(75 min · intermediate · developer audience). Maps the five locked sections
(**Fundamentals → Secure it → Scale it → Make it HA → Modernize it (incl. AI)**)
to slides, and ties each demo slide to its beat in [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md).

Reskins the existing 34-slide *"Azure SQL Hyperscale — The Cloud Database for the
era of AI"* deck from Zava → Collier Health / Ward General. Frame **every** beat as
an **on-prem delta**: *"here's what you do on your on-prem SQL Server today — here's
what's different in Hyperscale."*

Legend: 🖥️ live/recorded demo · 📊 slide only · 🎥 recording fallback needed

---

## 0. Fundamentals — the on-ramp (~12 min)

| # | Slide | Key content |
|---|---|---|
| 1 | **Title** | The Developer's Guide to Azure SQL Hyperscale · Bob Ward |
| 2 | **The hook** | "The SQL Server you already run — now secured, scaled, and made HA by the cloud, with new T-SQL you didn't have before, and no new database to adopt." |
| 3 | **Meet Ward General** | Collier Health system · `wardgeneral` Hyperscale DB · the patient-chart app; all data synthetic |
| 4 | **What Hyperscale *is*** | Same engine / same T-SQL; decoupled compute + page servers + log service + RBPEX (name-drop, don't deep-dive) |
| 5 | **Architecture at a glance** 📊 | [architecture/wardgeneral-architecture.svg](architecture/wardgeneral-architecture.svg) — app + DAL, in-app agent, DAB, engine, Foundry, replicas |
| 6 | **Build it** 🖥️ | Census board → chart; procs-for-everything via ADO.NET; passwordless. → *Beat: Build it* |

## 1. Secure it (~12 min)

| # | Slide | Key content |
|---|---|---|
| 7 | **Secure it — the on-prem delta** | On-prem you ship a login + password and guard it forever → cloud = **no secrets in your app** |
| 8 | **Passwordless / Entra-only** | Managed identity app→DB; no SQL logins, nothing to leak or rotate |
| 9 | **Row-Level Security** 🖥️ | "Viewing as" dropdown → board/chart narrow via `SESSION_CONTEXT`. → *Beat: Secure it* |
| 10 | **Protect the data** 📊 | Versionless CMK TDE (BYOK, auto-rotate) · Private Link · append-only ledger audit |
| 11 | **Defender for SQL** 📊 | Threat protection / vulnerability assessment (named, not demoed) |

## 2. Scale it — the primary demo (~18 min)

| # | Slide | Key content |
|---|---|---|
| 12 | **Scale it — the can't-do-on-prem moment** | 2 → 192 vCores, online rescale (a brief reconnect, not a maintenance window), no hardware to buy |
| 13 | **Compute ⟂ storage** 📊 | Scale compute with a slider; storage to 128 TB on actual allocation; no data movement |
| 14 | **HTAP on one DB** 🎥 | OLTP by day · analytics/ETL at night on the same `wardgeneral` |
| 15 | **Read scale-out** 🖥️ | Serverless named replica `wardgeneral-research` (autoscale 1→8), Research page vector search isolated from OLTP. → *Beat: Scale it* |
| 16 | **Elastic pools** 📊 | Many hospitals sharing a compute pool as Collier Health grows |

## 3. Make it HA (~10 min)

| # | Slide | Key content |
|---|---|---|
| 17 | **Make it HA — the on-prem delta** | On-prem HA is *your* job (WSFC, quorum, AGs, listeners) → built in |
| 18 | **Zone-redundant SLA** 📊 | 99.995% zone-redundant HA replica — no cluster to build |
| 19 | **Failover groups / geo** 🎥 | App keeps one endpoint through failover (recording, not live) |
| 20 | **What the app still owns** 🖥️ | Connection retry (`SqlRetryLogicOption` / `RetryPolicy`); `ApplicationIntent=ReadOnly` routing |

## 4. Modernize it — new T-SQL, many surfaces, AI (~20 min)

| # | Slide | Key content |
|---|---|---|
| 21 | **Modernize it — what's new since your on-prem box** | Document + text-mining + vector, all in the engine |
| 22 | **Native `json` type** 🖥️ | `IntakeJson` / `InsuranceJson` / `ResultJson` — stored, indexed, queried; JSON index. → *Beat: Modernize it* |
| 23 | **Regex in T-SQL** 🖥️ | `REGEXP_*` mines BP / HR / pain / follow-up from `ClinicalNote`; regex = deterministic, vectors = semantic on the *same* text |
| 24 | **One DB, many surfaces** 📊 | Blazor+ADO.NET → DAB (REST/GraphQL, no code) → MCP (agent tools); same 11 procs |
| 25 | **DAB + SQL MCP** 🖥️ | Copilot Agent mode calls the *same* procs as tools. → *Beat: DAB + MCP* |
| 26 | **AI in the engine** 🖥️ | `AI_GENERATE_EMBEDDINGS` + native `VECTOR` + DiskANN; `SELECT TOP (N) WITH APPROXIMATE` over 60k notes |
| 27 | **AI in the app** 🖥️ | Bedside assistance (RAG + gpt-5) + in-app MAF assistant; **RLS carries into the agent**. → *Beat: AI in the app* |
| 28 | **Why Hyperscale for AI** | One DB holds the vectors, the read replica, and the gpt-5 calls — no separate vector store to provision/sync/secure |

## Close (~3 min)

| # | Slide | Key content |
|---|---|---|
| 29 | **The through-line** | Same procs serve the app, REST/GraphQL, and the agent — one contract, many consumers |
| 30 | **Secured · Scaled · HA · Modernized** | The four verbs, on the SQL Server you already know |
| 31 | **Next / resources** | Points to the keynote (deep AI, Zava) + the *Azure SQL Hyperscale Unveiled* book |

---

## Open decisions (for Bob)

1. **Deck production fork:** reskin the existing 34-slide `.pptx` in place (Zava→Ward
   General), or build a fresh deck from this outline? (Existing has the Scale/HTAP
   visuals worth keeping.)
2. **AI scope tension:** the outline locked AI as a *tease* (keynote goes deep, on
   Zava). But this kit now has a full in-app MAF assistant + DAB/MCP. Options:
   keep AI to slides 26–27 as a tight tease that points to the keynote, **or**
   elevate it (we have the material). Recommend: keep the *tease* framing but let
   the in-app assistant be the memorable 90-second moment, explicitly handing off
   to the keynote.
3. **Timing:** Scale it is the primary demo (18 min); if AI creeps, trim slides
   14/16/19 to recordings.
