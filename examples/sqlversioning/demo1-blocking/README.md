# Demo 1 — Blocking

Proves the problem: readers block on writers under READ COMMITTED without versioning. Shows `NOLOCK` as the wrong fix (dirty reads).

## Scripts

| Script | Session | Purpose |
|--------|---------|---------|
| `demo1-blocking-session1.sql` | Session 1 (Writer) | Takes X-lock, blocks reader |
| `demo1-blocking-session2.sql` | Session 2 (Reader) | Blocked SELECT, NOLOCK dirty read proof |

## How to Run

### Browser app

Open `/demo/1`. The walkthrough shows one SQL batch at a time, its Writer,
Reader, or Admin session, and the actual result beside it. SQL is always visible,
just as it would be in an SSMS query window. Run executes only that batch;
Previous, Next, and the step picker do not execute anything.

- **Preparation:** configure locking and reset the balance to 100.
- **Reader waits:** writer changes 100 to 200 without committing; reader waits.
  Advance to the blocking query and writer COMMIT while the reader is running.
  The reader then returns 200.
- **NOLOCK reads dirty data:** writer makes another uncommitted change;
  NOLOCK can read it. Roll back, then read normally to see 200 again.
- **Finish:** run both cleanup batches, then click **Finish demo — close
  sessions** in the walkthrough and confirm. Wait for the connections-closed
  success message before starting Demo 2. Cleanup SQL by itself leaves the
  connections open. The header's End demo also closes them.

Detailed monitoring and earlier results are expandable. Session balances are
last returned SQL values, not estimates of the current committed balance.

### SSMS

1. Open each script in a separate SSMS query window
2. Execute blocks step-by-step, following the `>>> Go to Session N` cues
