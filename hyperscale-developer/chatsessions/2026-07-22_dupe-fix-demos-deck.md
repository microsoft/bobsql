# 2026-07-22 — Clinical-note dedup fix · demo run-of-show · deck outline

Handoff note (Bob is switching computers tomorrow). This machine is **left running
overnight** so the embeddings driver finishes. The embeddings + index land in the
**cloud DB** (`collierhealth-17` / `wardgeneral`), so verification works from any
machine via SQL.

## What got done today

1. **Clinical-note duplication fixed (94.75% → 0%).**
   - Root cause: the seed built every note as a deterministic function of
     `EncounterId` through correlated `CHOOSE(... % n)` picks → 60k rows collapsed
     to **3,150 distinct notes**, one shared timestamp.
   - Rewrote the generator: notes **anchored to the encounter's primary diagnosis**
     (coherent + cluster by condition for vector search) with **independent
     per-fragment `ABS(CHECKSUM(NEWID()))`** randomness + randomized `CreatedAt`.
   - Validated: **60,000 / 60,000 distinct (0% dupes)**, REGEXP tokens still
     extract, grammar clean.
   - Files: `build/sql/05-seed.sql` §10 (canonical); `build/sql/reseed-notes.sql`
     (targeted live-DB rebuild helper — patients/encounters/labs untouched);
     `build/sql/_dupe-check.sql` (re-verify tool). Book synced:
     `hyperscalebook/examples/ch02-getting-started/05-seed.sql` (only header prose differs).

2. **Live DB re-seeded** (notes only) + embeddings rebuild kicked off (see below).

3. **Architecture diagram** (`architecture/wardgeneral-architecture.svg`, backup
   `*.backup-20260722-142435.svg`): added in-app **MAF agent** (MCP client → DAB +
   gpt-5 direct, crimson/modernize box), small **Foundry reasoning** box, double-ended
   arrows (except writes), `sp_invoke_external_rest_endpoint`/`GenerateClinicalAssistance`
   in the "AI in the engine" box, **chat** labels on engine→APIM→Foundry, and **bolded**
   all real code identifiers (procs, T-SQL commands, VECTOR, DiskANN, gpt-5, DAL classes).

4. **Demo run-of-show** (`DEMO-RUNBOOK.md`): all 6 beats drafted; **Demo 1** and
   **Demo 2** finalized to Bob's spec (see below).

5. **Deck outline** (`deck-outline.md`): 31 slides across the 5 locked sections.

## Background job — embeddings (RUNNING overnight)

- Driver: `build/deploy/generate-embeddings.ps1` (this machine, terminal was id `32ee261d`).
- Re-embedding all 60k notes after the re-seed. **Latency-bound ~2000 / 15 min**
  (NOT TPM — deployment already at capacity 100 GlobalStandard). ETA ~7–8h → done overnight.
- Auto-builds the DiskANN index at the end. Resumable (`WHERE NOT EXISTS`).
- **Tomorrow, verify from the new machine (SQL against wardgeneral):**
  - `SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings;` → expect **60000**.
  - Confirm index exists: `sys.indexes` name `VIX_ClinicalNoteEmbeddings_Embedding`.
  - Run `build/sql/_dupe-check.sql` → expect ~0% dupes.
  - Sanity-check a vector search ("elderly chest pain with elevated troponin") → diverse hits.
  - If the run died partway: just re-run `generate-embeddings.ps1` (resumes).

## Demo numbering (Bob is driving the sequence)

- **Demo 1 — Build it / show the app** ✅ app tour (census → chart, procs via ADO.NET,
  passwordless) → **quick Azure portal look** at Hyperscale. Both **recorded as backups**.
- **Demo 2 — Secure it** ✅ Live: flip **"Viewing as"** (RLS narrows board/chart), flip back.
  Then show code IN ORDER (exact lines in the runbook's "Exact code to show" block):
  1. `WardGeneralConnectionFactory.cs` L48–71 — passwordless (`ActiveDirectoryDefault`, L58)
  2. `ChartRepository.cs` L261–279 — `OpenWithContextAsync` `sp_set_session_context` (L270–278)
  3. `10-row-level-security.sql` L48–63 — `fn_encounterAccess` predicate
  4. `10-row-level-security.sql` L71–76 — `EncounterAccessPolicy`
  TDE/CMK + Private Link + Defender = **slide-only**. **Ledger deferred to the AI-in-engine demo**.
- **Demo 3 — NEXT: START HERE TOMORROW.** Not yet defined. Runbook draft order after: Scale,
  Modernize, AI in the app, DAB+MCP. Reconcile with deck section order (deck folds DAB+MCP
  into Modernize; no live HA beat — HA is slides + a failover recording).

## Open decisions (in deck-outline "Open decisions")

1. **Deck production fork:** reskin the existing 34-slide Zava `.pptx` in place vs build fresh.
2. **AI scope:** outline locked AI as a *tease* → next-day keynote (Zava) goes deep. Rec: keep
   tease framing, let the in-app MAF assistant be the ~90s memorable moment.
3. **AI beat overlap:** Demo "AI in the app" and "DAB+MCP" both do similar-notes + assistance —
   pick ONE as the live AI moment, make the other a slide/mention.

## Uncommitted (Bob handles commits himself)

- **bwsql** (branch `bw`): `presentations/hyperscale-developer/` → `build/sql/05-seed.sql`,
  `build/sql/reseed-notes.sql`, `build/sql/_dupe-check.sql`,
  `architecture/wardgeneral-architecture.svg` (+ backup), `DEMO-RUNBOOK.md`,
  `deck-outline.md`, `BACKLOG.md`. (Note: `build/deploy/embeddings-progress.log` churns while running.)
- **hyperscalebook** (branch `bw`): `examples/ch02-getting-started/05-seed.sql`.
