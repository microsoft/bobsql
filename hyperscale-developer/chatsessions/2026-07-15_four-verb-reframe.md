# Chat session — 2026-07-15 · Four-verb reframe

## Where we left off

Author (Bob) proposed reframing the W25 talk spine from the deck's two feature
pillars → four **developer-outcome verbs**:

> **Secure it · Scale it · Make it Highly Available · Modernize it**

…where the first three are "from the app's perspective" and **Modernize it** = AI, DAB,
MCP, JSON, **regex**, vectors.

Decision: **write it up, keep discussing before changing the deck.** No slides built yet.

## What was done this session

- Added a **"Proposed reframe — the four developer verbs (author idea, 2026-07-15)"**
  section to [outline.md](../outline.md), directly after "The two demo pillars."
- Kept every existing slide→segment mapping; the reframe only re-labels the spine and
  slots in two new beats (regex + an explicit security beat).
- Mapped each verb → deck slides → demo state → strength today.
- Flagged the two weak legs (**Secure it**, **Make it HA**) and the one new beat
  (**regex**).

## The mapping (summary)

| Verb | Deck mapping | State | Strength |
|---|---|---|---|
| Secure it | Slide 27 (APIM); DAB managed-identity auth | recording/narrative | **weak leg** — only "responsible AI" today |
| Scale it | Seg C / Demo 1 (slides 9–16) | recorded/pre-deployed | strong (is Demo 1) |
| Make it HA | "10 reasons" (slide 16) + SLA slide | narrative/recording | **weak leg** — a bullet, not a beat |
| Modernize it | Seg E / Demo 2 (slides 17–28) + **regex** | recorded + live-TBD | strong (is Demo 2) |

## Open items to pick back up

1. **Secure it** — needs **1 new pillar slide.** Best real beat already deployed:
   DAB → `zavalending` over **managed identity, no secrets**. Rest (Entra-only, private
   endpoint, TDE/AE/RLS) named not demoed. Decide live-vs-recording.
2. **Make it HA** — needs **1 new pillar slide** + likely a recording. Only realistically
   live element = **read scale-out connection-string change** (`ApplicationIntent=ReadOnly`)
   + app **retry logic** (EF Core `EnableRetryOnFailure`). Failover = recording.
3. **Regex (Modernize)** — needs a **script + slide**, a **Learn syntax check**, and a
   **preview/GA-tag pass**. Candidate T-SQL: `REGEXP_LIKE` / `REGEXP_REPLACE` /
   `REGEXP_SUBSTR` / `REGEXP_COUNT` / `REGEXP_INSTR` to validate/parse loan data.
4. **Segment order & 75-min budget** — foundation verbs (Secure/Scale/HA) *before* the AI
   payoff; two new beats likely means trimming Seg B architecture (slides 6–7).

## Next action (author's choice)

Pick one to start building: the **Secure it** slide/beat, the **HA** slide/beat, or the
**regex** demo.

## Environment reminder (unchanged from outline)

- Zava Lending env still deployed; **DAB Container App `zavafin-loan-mcp` is stopped** —
  restart before any REST/MCP/Secure beat.
- Sub `AzureSQL_bobward` (`0efc44aa-c965-420f-aac4-fff305dbcc97`), RG `zavarg`,
  DB `zavafinsqlserver.database.windows.net/zavalending`.
