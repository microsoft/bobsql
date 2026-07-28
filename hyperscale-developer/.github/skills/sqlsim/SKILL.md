---
name: sqlsim
description: 'Run SQL scripts and ad-hoc queries against the Ward General Azure SQL Hyperscale database (and any SQL Server / Azure SQL) for the hyperscale-developer talk, using the sqlsim.exe bundled in this kit. Use when: deploying the sql/ scripts, running a quick query against wardgeneral, connection testing, or driving a multi-threaded / scale workload. Full Microsoft Entra support (token, interactive, managed identity) — the passwordless path that works when sqlcmd -G fails.'
---

# sqlsim — bundled SQL runner for the hyperscale-developer talk

This kit ships its own copy of `sqlsim.exe` so the whole presentation folder is
self-contained (the tool's source repo is not public). It is a standalone,
xcopy-deploy executable — the only dependency is **ODBC Driver 18 for SQL Server**.

Use this instead of `sqlcmd -G` (Entra-integrated `sqlcmd` fails on some machines
with "unknown error"). sqlsim's token path is the reliable passwordless option.

## Path (relative to the presentation root)
```
.\utilities\sqlsim\sqlsim.exe
```
Run commands from `presentations/hyperscale-developer/`, or substitute the full path.

## Live talk environment
- Server: `collierhealth-17.database.windows.net`
- Database: `wardgeneral` (Hyperscale HS_Gen5_8)
- Auth: Microsoft Entra as `bobward@microsoft.com`

## Entra authentication (choose one)
- `-T <token>` — Azure access token (most reliable; see example below)
- `-A` — Entra interactive (`ActiveDirectoryInteractive`, default)
- `-A ActiveDirectoryMsi` — managed identity (e.g. from App Service)
- `-E` — Windows integrated (local SQL Server only)

## Common commands

```powershell
# Ad-hoc query against wardgeneral via Entra token (the reliable path)
$token = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv)
& '.\utilities\sqlsim\sqlsim.exe' -S collierhealth-17.database.windows.net -d wardgeneral -T $token -Q "SELECT @@VERSION"

# Deploy a schema/seed script (GO batch separators handled natively)
& '.\utilities\sqlsim\sqlsim.exe' -S collierhealth-17.database.windows.net -d wardgeneral -T $token -i .\build\sql\05-seed.sql

# Entra interactive (no token needed, pops a browser)
& '.\utilities\sqlsim\sqlsim.exe' -S collierhealth-17.database.windows.net -d wardgeneral -A -Q "SELECT DB_NAME()"

# Multi-threaded scale workload: 16 threads x 100 iterations, quiet, with server stats
& '.\utilities\sqlsim\sqlsim.exe' -S collierhealth-17.database.windows.net -d wardgeneral -T $token -i .\workload.sql -n 16 -r 100 -q -querystats
```

## Notes
- `-q` quiet (metrics only), `-v` verbose, `-json` machine-readable, `-o <file>` tee output.
- `-R` read-only intent (route to an HA secondary) — for the "Make it HA" beat.
- `-Q`, `-i`, and `-workload` are mutually exclusive query sources.
- Exit code 0 = success, 1 = error.

Full parameter reference lives next to the binary: `utilities/sqlsim/sqlsim-usage.md`.
