# Demo 3 — Internals & Costs

Shows version chains at the page level using DBCC PAGE, proves cross-database contamination via the global XSN watermark, and explains ghost records vs version records.

## Scripts

| Script | Session | Purpose |
|--------|---------|---------|
| `demo3a-version-chain-session1.sql` | Session 1 (Reader) | RCSI single-version read, Snapshot chain-walk via DBCC PAGE |
| `demo3a-version-chain-session2.sql` | Session 2 (Writer) | Single UPDATE (Beat 1), three UPDATEs building 3-hop chain (Beat 2) |
| `demo3b-instance-wide-impact-session1.sql` | Session 1 (Culprit) | Forgotten snapshot in `eaglesdontfly`; fix = COMMIT |
| `demo3b-instance-wide-impact-session2.sql` | Session 2 (Victim OLTP) | 10 UPDATE waves on `howboutthemcowboys`; tempdb growth proof |
| `demo3c-ghost-records.sql` | Single session | DELETE creates both ghost record and version record |

## Dependencies

### Python Packages

```
pip install flask mssql-python
```

### DBCC PAGE Viewer

Start before demo3a:

```
python dbcc_page_viewer.py
# Open http://localhost:5050
```

## How to Run

For multi-session scripts, open each `-session1` / `-session2` file in a separate SSMS window and follow the `>>> Go to Session N` cues.
