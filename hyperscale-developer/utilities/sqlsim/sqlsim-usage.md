---
name: sqlsim
description: 'Execute .sql script files against SQL Server and Azure SQL databases using sqlsim. Use when: deploying SQL scripts, running .sql files with GO batch separators, executing SQL files against databases, running multi-threaded workloads, replaying XEvent traces, connection stress testing.'
---

# sqlsim — SQL Workload Simulator

## When to Use
- Executing `.sql` script files against databases
- Deploying SQL scripts that contain GO batch separators
- Running SQL files against Azure SQL or local SQL Server instances
- Multi-threaded workload simulation and stress testing
- Connection testing and stress testing
- Replaying XEvent traces captured from production
- Running mixed workloads from JSON definition files
- Performance measurement with per-query server statistics

## Path
```
.\utilities\sqlsim\sqlsim.exe
```
> Bundled with this presentation kit. Paths below are relative to the presentation
> root (`presentations/hyperscale-developer/`) — run from there, or substitute the
> full path. Standalone: only ODBC Driver 18 is required, no install.

## Prerequisites
- ODBC Driver 18 for SQL Server (only dependency)
- Azure CLI (only if using `-T` token authentication)

## Authentication

- **Local SQL Server**: Use `-E` for Windows integrated authentication
- **Azure SQL / Fabric**: Use `-T $token` with an Azure access token, or `-A` for Entra interactive
- **SQL Authentication**: Use `-U <username> -P <password>`
- **Managed Identity**: Use `-A ActiveDirectoryMsi`

## Usage

```powershell
# Local SQL Server with Windows auth
& '.\utilities\sqlsim\sqlsim.exe' -S localhost -d master -E -i <script.sql>

# Single ad-hoc query
& '.\utilities\sqlsim\sqlsim.exe' -S localhost -d master -E -Q "SELECT @@VERSION"

# Connection test only (no query)
& '.\utilities\sqlsim\sqlsim.exe' -S localhost -E

# Azure SQL with access token
$token = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv)
& '.\utilities\sqlsim\sqlsim.exe' -S <server> -d <database> -T $token -i <script.sql>

# Azure SQL with Entra interactive auth
& '.\utilities\sqlsim\sqlsim.exe' -S myserver.database.windows.net -d mydb -A -Q "SELECT 1"

# Multi-threaded workload: 10 threads, 50 iterations each, quiet mode
& '.\utilities\sqlsim\sqlsim.exe' -S localhost -d testdb -E -Q "SELECT COUNT(*) FROM Orders" -n 10 -r 50 -q

# Mixed workload from JSON definition
& '.\utilities\sqlsim\sqlsim.exe' -S localhost -d testdb -E -workload workload.json

# With per-query server statistics
& '.\utilities\sqlsim\sqlsim.exe' -S localhost -d testdb -E -i queries.sql -n 10 -r 50 -q -querystats
```

## Complete Parameter Reference

### Connection Options (one method required)

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-c <conn_string>` | Complete ODBC connection string (mutually exclusive with `-S`/`-d`/`-E`/`-U`/`-P`) | `-c "Driver={ODBC Driver 18 for SQL Server};Server=localhost;..."` |
| `-S <server>` | Server name (defaults to `localhost` if omitted) | `-S localhost`, `-S server\instance`, `-S myserver.database.windows.net` |
| `-d <database>` | Database name (optional for SQL Server, required for Azure SQL) | `-d master` |

### Authentication (choose one)

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-E` | Windows integrated authentication | `-E` |
| `-A [mode]` | Microsoft Entra auth. Modes: `ActiveDirectoryInteractive` (default), `ActiveDirectoryMsi` | `-A`, `-A ActiveDirectoryMsi` |
| `-T <token>` | Access token authentication | `-T $token` |
| `-U <username>` | SQL username (or identity GUID for user-assigned managed identity) | `-U myuser` |
| `-P <password>` | SQL password (use with `-U`) | `-P mypass` |

### Query Source (optional — omit all for connection test)

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-Q <query>` | Inline query (GO on its own line separates batches, max 1 MB) | `-Q "SELECT @@VERSION"` |
| `-i <file>` | SQL script file (GO separates batches, size limited by memory) | `-i queries.sql` |
| `-workload <json>` | Mixed workload from JSON definition file | `-workload workload.json` |
| `-replay <mode>` | Replay XEvent trace: `fast` (per-session fidelity) or `stress` (max throughput) | `-replay fast` |
| `-replayfile <xml>` | XML replay file from `convert-xel.ps1` (use with `-replay`) | `-replayfile trace.xml` |

> **Note:** `-Q`, `-i`, `-workload`, and `-replay` are mutually exclusive.

### Workload Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-n <threads>` | Number of concurrent threads | 1 |
| `-r <iterations>` | Iterations per thread | 1 |
| `-p` | Use prepared statements (SQLPrepare/SQLExecute) | false |
| `-reconnect` | Disconnect and reconnect after each iteration | false |
| `-usepool` | Enable ODBC connection pooling (requires `-reconnect`) | false |

### Connection Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-l <seconds>` | Login timeout (0-86400) | driver default |
| `-t <seconds>` | Query timeout (0-86400) | driver default |
| `-app <name>` | Application name for connection tracking | `sqlsim` |
| `-retry <count>` | Connection retry attempts (0-255) | 1 |
| `-retrydelay <seconds>` | Seconds between retries (1-60) | 10 |

### Security & Encryption

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-N [level]` | TDS 8.0 encryption: `o` (optional), `m` (mandatory), `s` (strict) | `m` |
| `-C` | Trust server certificate (bypass validation) | false |
| `-F <hostname>` | Expected certificate hostname for validation (mutually exclusive with `-C`) | — |

### High Availability

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-R` | Read-only application intent (route to AG secondary) | false |
| `-M` | Multi-subnet failover (faster AG failover) | false |

### Error Handling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-stoponerror` | Stop on first error | false |

### Output Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-o <file>` | Write all output to file (like sqlcmd `-o`) | — |
| `-q` | Quiet mode (suppress query results, still shows metrics) | false |
| `-v` | Verbose mode (detailed execution phases and command echo) | false |
| `-querystats` | Per-query server statistics (SET STATISTICS TIME/IO aggregated across threads) | false |
| `-json` | Output in JSON format (machine-readable) | false |
| `-h`, `-?`, `--help` | Show help | — |
| `--version` | Show version | — |

## Parameter Conflicts

These combinations are mutually exclusive and will error at startup:

- `-Q` with `-i` — choose one query source
- `-T` with `-E`, `-A`, or `-U`/`-P` — choose one auth method
- `-F` with `-C` — can't validate and trust at the same time
- `-usepool` without `-reconnect` — pooling only applies when reconnecting
- `-c` with `-S`/`-d`/`-E`/`-U`/`-P` — connection string vs individual params
- `-replay` with `-Q`, `-i`, or `-workload` — choose one query source
- `-p` with `-replay` — replay uses its own ODBC methods
- `-reconnect` with `-replay` — replay manages its own connections

## Parameter Format
- Space-separated or concatenated: `-S localhost` and `-Slocalhost` both work
- Both styles can be mixed in the same command
- Quotes only needed for values with spaces or special characters

## Exit Codes
- **0**: Success — all queries completed
- **1**: Error — connection failed, invalid parameters, or execution errors

## Key Capabilities
- Handles GO batch separators natively
- Lightweight standalone executable (xcopy deploy, no installer)
- Native builds for Windows x64 and ARM64
- Supports SQL Server, Azure SQL DB, Azure SQL MI, Fabric SQL DB, Fabric Warehouse, Azure Synapse
- Multi-threaded workload simulation with `-n` and `-r`
- XEvent trace replay with `-replay fast` or `-replay stress`
- Mixed workload definitions via `-workload` JSON files
- Per-query server statistics with `-querystats`
- JSON output for automation pipelines with `-json`
- Full Unicode support (UTF-8 input/output)
- All output lines are timestamped (`YYYY-MM-DD HH:MM:SS.mmm |`)
