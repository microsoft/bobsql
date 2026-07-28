# Chat session — 2026-07-19 (pt.2) · Scenario switch to Collier Health / Ward General

Builds on [2026-07-19_rebalance-onprem-audience.md](2026-07-19_rebalance-onprem-audience.md).

## Decisions this session

1. **Folder renamed/moved** → `presentations/hyperscale-developer/` (was
   `vslivemsft2026/w25-hyperscale-developers-guide/`). Talk is now a **reusable, event-
   independent asset** (delivered again at other events).
2. **Show an actual C# application.** Only existing C# apps were ZavaLiveSite (excluded)
   and two connection test harnesses (not business apps) → need to build one.
3. **Scenario switched: Zava Lending → the book's Collier Health / Ward General
   healthcare scenario.** Reverses the prior "Zava, book stays in book" ground rule.
   Rationale: keynote's AI demo is Zava, so healthcare here = zero overlap; and Bob has
   to write the book's Ch 4 app anyway — build once, use for book + every talk delivery.

## Why it fits (book already did the hard part)

- **Schema built + seeded + validated** in `hyperscalebook/examples/ch02-getting-started/`
  (`01-schemas.sql`→`05-seed.sql`): `clinical`+`ops`, 13 tables, `vPatientChart` view,
  native `json` (`Patient.InsuranceJson`, `Encounter.IntakeJson`, `LabResult.ResultJson`),
  `ClinicalNote` free text, `Observation` high-ingest. Stored procs exist.
- **App specced but NOT built** — `hyperscalebook/examples/ch04/` is empty. Ch 4 locks the
  stack: **.NET 10 + `Microsoft.Data.SqlClient` (raw ADO.NET, no ORM), stored-proc DAL**,
  Entra-only auth, retry policy.

## Four verbs → book chapters

| Verb | Chapter | Hook |
|---|---|---|
| Secure it | Ch 8 | Entra/MI = no secrets; `vPatientChart` = built-in PHI boundary; RLS |
| Scale it | Ch 10 | grow `Observation`, named replicas, scale compute |
| Make it HA | Ch 9 | 4-replica failover; app-side retry (`retry-policy.cs`) |
| Modernize — new T-SQL | Ch 5 | native `json` cols + `REGEXP_*` on `ClinicalNote` |
| AI | Ch 5/6 | embed `ClinicalNote` → vector search + `WITH APPROXIMATE` |

**AI angle = clinical-notes semantic search.** Same-column synergy: regex = deterministic
extraction (MRN, BP, ICD-10, doses), vectors = semantic similarity ("similar clinical
presentation"). Real beat now (~5–7 min), keynote still the deep dive.

**Book boundary preserved:** Ch 4 app = CRUD only; clinical-notes AI = Ch 6 extension.
Talk shows both; book keeps them in their chapters.

## What was done this session (files)

- Rewired [outline.md](../outline.md) Zava → Ward General: ground rules, deployed-env
  table (book-locked names: `collierhealth`/`wardgeneral`/`rg-collierhealth`/
  `id-collierhealth`/`wardgeneral-app`), reframe table, Secure/HA/Modernize/AI beats,
  demo-asset inventory, pre-flight checklist, open decisions. Marked the `.pptx` and the
  detailed A–G sections **Zava-era, pending rewrite**.
- Updated [README.md](../README.md): scenario + reusable-asset framing + status.

## Next (pick back up here)

- **Build the Ch 4 app** `hyperscalebook/examples/ch04/app/` (.NET 10, `Microsoft.Data.SqlClient`,
  stored procs, MI auth, retry). ← the "actual application" the talk needs.
- Confirm/provision `wardgeneral` (examples/ch02 scripts).
- Write JSON + Regex SSMS scripts on `wardgeneral` (`ClinicalNote`, the 3 json columns).
- Build the AI beat (embed `ClinicalNote`, vector index, search proc).
- Rewrite outline A–G + reskin the deck to Ward General.
