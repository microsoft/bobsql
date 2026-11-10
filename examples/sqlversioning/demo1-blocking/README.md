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
The right side keeps Writer and Reader results side by side, including live
blocking evidence and their last returned balances. There is no Admin column;
admin-query results appear below the SQL step on the left.

- **Preparation:** configure locking and reset the balance to 100.
- **Reader waits:** writer changes 100 to 200 without committing; reader waits.
  Advance to the blocking query and writer COMMIT while the reader is running.
  The reader then returns 200.
- **NOLOCK reads dirty data:** step 8 returns the writer's actual uncommitted
  balance of 1000199.00; step 9 reads it with NOLOCK. Step 10 rolls back and
  returns 200.00 in the Writer pane, while the Reader retains its dirty-read
  result until step 11 reads normally and returns 200.00 too.
- **Finish:** run both cleanup batches, then click **Finish demo — close
  sessions** in the walkthrough and confirm. Wait for the connections-closed
  success message before starting Demo 2. Cleanup SQL by itself leaves the
  connections open. The header's End demo also closes them.

Earlier results are expandable; background monitoring still supplies live
blocking and session state. Session balances are
last returned SQL values, not estimates of the current committed balance.
To start over, confirm **Reset demo 1**. It rolls back open transactions,
sets Account 1 back to 100.00, restores locking READ COMMITTED's database
settings, closes the app sessions, and returns to step 1 with progress cleared.
Unlike End demo, it also undoes the walkthrough's committed balance change.

### SSMS

1. Open each script in a separate SSMS query window
2. Execute blocks step-by-step, following the `>>> Go to Session N` cues
