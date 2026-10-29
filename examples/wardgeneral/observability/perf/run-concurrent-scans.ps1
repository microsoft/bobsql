<#
.SYNOPSIS
    Run three concurrent copies of the Observability observation scan.

.DESCRIPTION
    Starts exactly three new sqlcmd processes against wardgeneral, captures each
    session's STATISTICS IO and STATISTICS TIME output separately, and prints a
    compact summary plus the UTC interval to inspect in Azure Monitor.

    The workload is read-only, but each session scans clinical.Observation and
    consumes substantial CPU. Do not run it against a production database.

    A cold compute cache cannot be created from this script. On cold compute,
    at least one session can report page-server reads or page-server read-ahead
    reads. On warm compute, zero is the correct result: the reads were served by
    the buffer pool or RBPEX. -ExpectColdCache turns absence of page-server
    evidence into a clear failure instead of silently claiming a cold run.

.PARAMETER Server
    Azure SQL logical-server FQDN. Defaults to WardGeneral__Server, including a
    value loaded from first-app/wardgeneral.env when that file exists.

.PARAMETER Database
    Database name. Defaults to WardGeneral__Database, then wardgeneral.

.PARAMETER SqlCmd
    Explicit path to the new sqlcmd. Defaults to SQLCMD and the standard install
    locations. The legacy ODBC sqlcmd is rejected.

.PARAMETER OutputDirectory
    Directory for the three captured session outputs. Defaults to a timestamped
    folder beneath the current user's temporary directory.

.PARAMETER ExpectColdCache
    Fail after the scans when no session reports page-server reads or
    page-server read-ahead reads.

.EXAMPLE
    ./run-concurrent-scans.ps1

.EXAMPLE
    ./run-concurrent-scans.ps1 -ExpectColdCache
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd,
    [string] $OutputDirectory,
    [switch] $ExpectColdCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server <your-server>.database.windows.net.'
}

$isGoSqlcmd = {
    param([string] $Executable)
    if (-not $Executable) { return $false }
    & $Executable --version 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\sqlcmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) -and (& $isGoSqlcmd $_) } |
    Select-Object -First 1

if (-not $sqlcmdPath) {
    throw @'
The new sqlcmd was not found. Install it with:

  winget install --id Microsoft.Sqlcmd

Then open a new PowerShell session, or set SQLCMD to its full path. The legacy
ODBC sqlcmd is skipped because its -G option cannot select the passwordless
DefaultAzureCredential flow used by this example.
'@
}

$queryPath = Join-Path $here 'observe-scan.sql'
if (-not (Test-Path $queryPath)) { throw "Missing SQL script: $queryPath" }

if (-not $OutputDirectory) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) "wardgeneral-observability-$stamp"
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

Write-Host 'Observability — three concurrent observation scans' -ForegroundColor Cyan
Write-Host "Server   : $Server" -ForegroundColor Gray
Write-Host "Database : $Database" -ForegroundColor Gray
Write-Host "Output   : $OutputDirectory" -ForegroundColor Gray
Write-Host ''
Write-Host 'Starting three read-only scans...' -ForegroundColor Yellow

$startedAtUtc = [DateTime]::UtcNow
$runs = foreach ($number in 1..3) {
    $outputPath = Join-Path $OutputDirectory "session-$number.txt"
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $sqlcmdPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($argument in @(
        '-S', $Server,
        '-d', $Database,
        '-G', '-C', '-b',
        '-i', $queryPath,
        '-o', $outputPath
    )) {
        $null = $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    if (-not $process.Start()) { throw "Could not start scan session $number." }

    [pscustomobject]@{
        Session = $number
        Process = $process
        Stopwatch = $stopwatch
        OutputPath = $outputPath
    }
}

foreach ($run in $runs) {
    $run.Process.WaitForExit()
    $run.Stopwatch.Stop()
}
$finishedAtUtc = [DateTime]::UtcNow

$summary = foreach ($run in $runs) {
    $raw = if (Test-Path $run.OutputPath) {
        Get-Content -LiteralPath $run.OutputPath -Raw
    }
    else {
        ''
    }

    $io = [regex]::Match(
        $raw,
        "Table '\[clinical\]\.\[Observation\]'.*?logical reads (?<logical>\d+).*?page server reads (?<pageServer>\d+).*?page server read-ahead reads (?<pageServerReadAhead>\d+)",
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    $timings = [regex]::Matches(
        $raw,
        'CPU time =\s*(?<cpu>\d+) ms,\s*elapsed time =\s*(?<elapsed>\d+) ms\.'
    )
    $timing = if ($timings.Count -gt 0) { $timings[$timings.Count - 1] } else { $null }

    [pscustomobject]@{
        Session = $run.Session
        ExitCode = $run.Process.ExitCode
        ProcessSeconds = [math]::Round($run.Stopwatch.Elapsed.TotalSeconds, 2)
        QueryCpuMs = if ($timing) { [int64]$timing.Groups['cpu'].Value } else { $null }
        QueryElapsedMs = if ($timing) { [int64]$timing.Groups['elapsed'].Value } else { $null }
        LogicalReads = if ($io.Success) { [int64]$io.Groups['logical'].Value } else { $null }
        PageServerReads = if ($io.Success) { [int64]$io.Groups['pageServer'].Value } else { $null }
        PageServerReadAhead = if ($io.Success) { [int64]$io.Groups['pageServerReadAhead'].Value } else { $null }
        Output = $run.OutputPath
    }
}

Write-Host ''
$summary | Format-Table Session, ExitCode, ProcessSeconds, QueryCpuMs,
    QueryElapsedMs, LogicalReads, PageServerReads, PageServerReadAhead -AutoSize
Write-Host ("Investigation window (UTC): {0:yyyy-MM-dd HH:mm:ss} through {1:yyyy-MM-dd HH:mm:ss}" -f $startedAtUtc, $finishedAtUtc) -ForegroundColor Green
Write-Host "Session details: $OutputDirectory" -ForegroundColor Gray

$failed = @($summary | Where-Object { $_.ExitCode -ne 0 -or $null -eq $_.LogicalReads })
if ($failed.Count -gt 0) {
    throw "One or more scan sessions failed or returned incomplete statistics. Read the session files in $OutputDirectory."
}

$pageServerPages = ($summary | Measure-Object -Property PageServerReads -Sum).Sum +
    ($summary | Measure-Object -Property PageServerReadAhead -Sum).Sum
if ($pageServerPages -gt 0) {
    Write-Host ("Page-server evidence found: {0:N0} pages across the three sessions." -f $pageServerPages) -ForegroundColor Green
}
elseif ($ExpectColdCache) {
    throw @'
No page-server reads were observed. The compute cache was already warm.
DBCC DROPCLEANBUFFERS would clear the buffer pool but not RBPEX, so this script
does not pretend it can manufacture a cold Hyperscale cache. Use the CPU and
logical-read evidence from this run, or repeat after the database moves to new
compute as part of an independently planned operation.
'@
}
else {
    Write-Host 'No page-server reads: this run was served by the buffer pool or RBPEX.' -ForegroundColor Yellow
}