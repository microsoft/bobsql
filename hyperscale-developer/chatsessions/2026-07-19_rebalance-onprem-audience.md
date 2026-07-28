# Chat session — 2026-07-19 · Rebalance for on-prem-dev audience

Builds on [2026-07-15_four-verb-reframe.md](2026-07-15_four-verb-reframe.md). Four-verb
spine kept; the balance changed.

## New direction from author (2026-07-19)

1. **Audience = developers who know on-prem SQL Server.** Frame every beat as a delta:
   "here's what you do on-prem, here's what's different/new/better in Hyperscale."
2. **Scale it = the primary demo** (the can't-do-on-prem moment: 32 → 192 vCores, no
   downtime, no hardware).
3. **AI = tease only.** The deep AI story is the **keynote the next day** — here it's one
   short (~5 min) recorded beat that points forward. Do not rebuild the keynote.
4. **Grow the developer-facing beats:** **Secure it**, **Make it HA**, and a NEW
   **"new T-SQL"** beat — **JSON + Regex** — run **live in SSMS**.

## What was done this session

- Verified regex on Learn (2026-07-19): `REGEXP_LIKE` / `REGEXP_REPLACE` /
  `REGEXP_SUBSTR` / `REGEXP_INSTR` / `REGEXP_COUNT` / `REGEXP_MATCHES` /
  `REGEXP_SPLIT_TO_TABLE` are **GA on SQL Server 2025 + Azure SQL Database** — no preview
  tag, safe to demo live. Native binary `json` type also GA.
- Updated [outline.md](../outline.md):
  - Ground rules: added on-prem-dev audience + "AI is a tease" rules.
  - Reframe section: added "Rebalance (2026-07-19)" note + new role table (Scale=primary,
    AI=tease, JSON+Regex=new live payoff). New one-liner (on-prem framing).
  - Split "Modernize it" into **new-T-SQL (live JSON+Regex)** + **AI tease**.
  - Added on-prem-delta lead-ins to **Secure it** (login+password vs managed identity)
    and **Make it HA** (you build WSFC/AG on-prem vs built-in).
  - Replaced the time budget with the **four-verb spine** (authoritative).

## New four-verb time budget (authoritative)

| # | Content | Slides | Min |
|---|---|---|--:|
| 1 | Title + hook (on-prem framing) | 1–2 | 3 |
| 2 | What Hyperscale is (vs on-prem) | 3–8 | 8 |
| 3 | **Scale it** — Demo 1 (32→192 + HTAP) | 9–16 | 15 |
| 4 | **Secure it** — delta from on-prem | new + 27 | 8 |
| 5 | **Make it HA** — delta from on-prem | new + 16 | 8 |
| 6 | **Modernize — new T-SQL** (JSON + Regex, live) | 17 + new | 12 |
| 7 | **AI tease** (→ keynote) | 18–28 trimmed | 5 |
| 8 | Close (DP-800, learn more) | 32–34 | 4 |

≈63 min + Q&A.

## Still to build / decide (pick back up here)

1. **New-T-SQL demo (JSON + Regex)** — SSMS script against `zavalending` + a slide.
   Real Zava use for regex: validate/parse SSN, email, phone, routing numbers. **Not
   built yet.**
2. **Secure it** — 1 new pillar slide; decide live-vs-recording for the managed-identity
   "no secrets" beat.
3. **Make it HA** — 1 new pillar slide; read-scale-out connection string
   (`ApplicationIntent=ReadOnly`) is the only realistically-live element; failover =
   recording.
4. **AI tease** — trim Demo 2 (slides 18–28) down to one recorded ~5-min beat with an
   explicit "see the keynote tomorrow" call-forward.
5. **Reconcile detailed sections A–G** in outline.md — they still reflect the pre-rebalance
   two-pillar order.

## Environment reminder (unchanged)

- Zava Lending env deployed; **DAB Container App `zavafin-loan-mcp` is stopped** — restart
  before any REST/MCP beat. Sub `0efc44aa-c965-420f-aac4-fff305dbcc97`, RG `zavarg`,
  DB `zavafinsqlserver.database.windows.net/zavalending`.
