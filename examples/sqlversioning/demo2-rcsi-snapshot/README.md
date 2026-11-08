# Demo 2 — RCSI and Snapshot Isolation

Five sub-demos covering RCSI as the right fix for reader/writer blocking, statement-level vs transaction-level consistency, snapshot write conflicts, and FK edge cases.

## Scripts

| Script | Session | Purpose |
|--------|---------|---------|
| `demo2a-rcsi-session1.sql` | Session 1 (Writer) | Enable RCSI, hold X lock, commit |
| `demo2a-rcsi-session2.sql` | Session 2 (Reader) | RCSI non-blocking read; READCOMMITTEDLOCK opt-in |
| `demo2b-rcsi-vs-snapshot-session1.sql` | Session 1 (Reader) | Two reads: RCSI sees change, Snapshot stays frozen |
| `demo2b-rcsi-vs-snapshot-session2.sql` | Session 2 (Writer) | UPDATE between reads |
| `demo2c-snapshot-conflict-session1.sql` | Session 1 (Snapshot Writer) | Conflicting update → error 3960 |
| `demo2c-snapshot-conflict-session2.sql` | Session 2 (Conflicting Writer) | Modify same row and commit first |
| `demo2d-fk-slock.sql` | Single session | FK validation still takes S locks under RCSI |
| `demo2e-fk-scan-conflict-session1.sql` | Session 1 (Snapshot) | DELETE order → error 3960 from FK range scan |
| `demo2e-fk-scan-conflict-session2.sql` | Session 2 (Writer) | UPDATE unrelated OrderItem triggers conflict |

## How to Run

For multi-session scripts, open each `-session1` / `-session2` file in a separate SSMS window and follow the `>>> Go to Session N` cues.
