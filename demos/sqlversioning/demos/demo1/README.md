# Demo 1 — Why Versioning?

Proves the problem: readers block on writers under READ COMMITTED without versioning. Shows `NOLOCK` as the wrong fix (dirty reads).

## Scripts

| Script | Session | Purpose |
|--------|---------|---------|
| `demo1-blocking-session1.sql` | Session 1 (Writer) | Takes X-lock, blocks reader |
| `demo1-blocking-session2.sql` | Session 2 (Reader) | Blocked SELECT, NOLOCK dirty read proof |

## How to Run

1. Open each script in a separate SSMS query window
2. Execute blocks step-by-step, following the `>>> Go to Session N` cues
