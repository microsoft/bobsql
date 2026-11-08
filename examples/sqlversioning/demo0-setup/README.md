# Demo 0 — Setup

One-time setup script that creates all databases and seed data for the session.

## Script

| Script | Purpose |
|--------|---------|
| `demo0-setup.sql` | Creates 3 databases, tables, and seed data |

## Databases Created

| Database | Purpose |
|----------|---------|
| `texasrangerswillwinitthisyear` | Primary demo database — Accounts, Orders, BigTable, BenchAccounts |
| `eaglesdontfly` | Cross-database version store / PVS isolation tests |
| `howboutthemcowboys` | Victim OLTP database for cross-DB version bloat demos |

## Usage

Run `demo0-setup.sql` in SSMS before any other demo. Idempotent — safe to re-run.
