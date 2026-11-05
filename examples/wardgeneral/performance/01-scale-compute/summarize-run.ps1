<#
.SYNOPSIS
    Builds the Demo 1 three-phase performance summary and comparison chart.

.EXAMPLE
    ./summarize-run.ps1 -RunDirectory C:\evidence\performance-stage1\runs\20260912-120000Z
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RunDirectory,

    [switch] $AllowPartial
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$metadataPath = Join-Path $RunDirectory 'run-metadata.json'
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Missing run metadata: $metadataPath"
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if (-not $AllowPartial -and $metadata.phases.Count -ne 3) {
    throw "Expected three completed phases; found $($metadata.phases.Count)."
}

$invariant = [System.Globalization.CultureInfo]::InvariantCulture

function Convert-ToDouble([string] $Value) {
    [double]::Parse($Value, $invariant)
}

function Get-RequiredText([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing evidence file: $Path"
    }
    Get-Content -LiteralPath $Path -Raw
}

function Get-RegexValue([string] $Text, [string] $Pattern, [string] $Label) {
    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) { throw "Could not parse $Label." }
    $match.Groups[1].Value
}

function Get-WaitMs([string] $Text, [string] $WaitName) {
    $match = [regex]::Match(
        $Text,
        "\| $([regex]::Escape($WaitName)) \| \d+ \| (\d+) \|")
    if ($match.Success) { return [long]$match.Groups[1].Value }
    return 0L
}

function Get-RbioWaitMs([string] $Text) {
    $total = 0L
    foreach ($match in [regex]::Matches($Text, '\| RBIO_RG_[A-Z_]+ \| \d+ \| (\d+) \|')) {
        $total += [long]$match.Groups[1].Value
    }
    $total
}

function Get-ProcedureStats([string] $Text) {
    $stats = @{}
    foreach ($match in [regex]::Matches(
        $Text,
        '\| (clinical\.(?:GetPatientChart|RecordVitals|PlaceMedicationOrder|FileLabResult|AddClinicalNote)) \| (\d+) \| ([0-9.]+) \| ([0-9.]+) \|')) {
        $stats[$match.Groups[1].Value] = [pscustomobject]@{
            Executions = [long]$match.Groups[2].Value
            AverageDurationMs = Convert-ToDouble $match.Groups[3].Value
            AverageCpuMs = Convert-ToDouble $match.Groups[4].Value
        }
    }
    $stats
}

function Get-ProcedureDelta([hashtable] $Before, [hashtable] $After) {
    $procedureOrder = @(
        'clinical.GetPatientChart',
        'clinical.RecordVitals',
        'clinical.PlaceMedicationOrder',
        'clinical.FileLabResult',
        'clinical.AddClinicalNote'
    )

    foreach ($name in $procedureOrder) {
        if (-not $After.ContainsKey($name)) {
            throw "Missing Query Store evidence for $name."
        }

        $afterRow = $After[$name]
        $beforeRow = if ($Before.ContainsKey($name)) { $Before[$name] } else { $null }
        $beforeExecutions = if ($beforeRow) { $beforeRow.Executions } else { 0L }
        $beforeDurationTotal = if ($beforeRow) {
            $beforeRow.AverageDurationMs * $beforeRow.Executions
        }
        else { 0.0 }
        $beforeCpuTotal = if ($beforeRow) {
            $beforeRow.AverageCpuMs * $beforeRow.Executions
        }
        else { 0.0 }
        $phaseExecutions = $afterRow.Executions - $beforeExecutions
        if ($phaseExecutions -le 0) {
            throw "Query Store execution count did not increase for $name."
        }

        $phaseDurationTotal =
            ($afterRow.AverageDurationMs * $afterRow.Executions) - $beforeDurationTotal
        $phaseCpuTotal =
            ($afterRow.AverageCpuMs * $afterRow.Executions) - $beforeCpuTotal
        $averageDurationMs = [Math]::Round(
            $phaseDurationTotal / $phaseExecutions, 3)
        $averageCpuMs = [Math]::Round(
            $phaseCpuTotal / $phaseExecutions, 3)

        [pscustomobject]@{
            Procedure = $name
            Executions = $phaseExecutions
            AverageDurationMs = $averageDurationMs
            AverageCpuMs = $averageCpuMs
        }
    }
}

function Get-ResourcePeaks([string] $Text, [datetime] $StartUtc, [datetime] $EndUtc) {
    $rows = foreach ($match in [regex]::Matches(
        $Text,
        '\| (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) \| ((?:\d+)?\.\d+) \| ((?:\d+)?\.\d+) \| ((?:\d+)?\.\d+) \| ((?:\d+)?\.\d+) \| ((?:\d+)?\.\d+)')) {
        $stamp = [datetime]::SpecifyKind(
            [datetime]::Parse($match.Groups[1].Value, $invariant),
            [System.DateTimeKind]::Utc)
        if ($stamp -ge $StartUtc -and $stamp -le $EndUtc) {
            [pscustomobject]@{
                Cpu = Convert-ToDouble $match.Groups[2].Value
                DataIo = Convert-ToDouble $match.Groups[3].Value
                LogWrite = Convert-ToDouble $match.Groups[4].Value
                Workers = Convert-ToDouble $match.Groups[5].Value
                Sessions = Convert-ToDouble $match.Groups[6].Value
            }
        }
    }

    if (-not $rows) { throw 'No resource-stat rows matched the phase UTC interval.' }

    [pscustomobject]@{
        Cpu = ($rows | Measure-Object Cpu -Maximum).Maximum
        DataIo = ($rows | Measure-Object DataIo -Maximum).Maximum
        LogWrite = ($rows | Measure-Object LogWrite -Maximum).Maximum
        Workers = ($rows | Measure-Object Workers -Maximum).Maximum
        Sessions = ($rows | Measure-Object Sessions -Maximum).Maximum
    }
}

$summary = foreach ($phase in $metadata.phases) {
    $phaseName = $phase.serviceObjective.ToLowerInvariant()
    $sqlsimText = Get-RequiredText (Join-Path $RunDirectory "sqlsim-$phaseName.txt")
    $serverBefore = Get-RequiredText (Join-Path $RunDirectory "server-$phaseName-before.txt")
    $serverAfter = Get-RequiredText (Join-Path $RunDirectory "server-$phaseName-after.txt")
    $networkBefore = Get-Content `
        -LiteralPath (Join-Path $RunDirectory "network-$phaseName-before.json") `
        -Raw | ConvertFrom-Json
    $networkAfter = Get-Content `
        -LiteralPath (Join-Path $RunDirectory "network-$phaseName-after.json") `
        -Raw | ConvertFrom-Json
    $procedureStats = Get-ProcedureDelta `
        (Get-ProcedureStats $serverBefore) `
        (Get-ProcedureStats $serverAfter)

    $successLine = [regex]::Match(
        $sqlsimText,
        'Avg Elapsed: ([0-9.]+) ms \((\d+) successful, (\d+) failed\)')
    if (-not $successLine.Success) { throw "Could not parse sqlsim totals for $($phase.serviceObjective)." }

    $dateStyles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
        [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $startUtc = [datetimeoffset]::Parse(
        $phase.startedAtUtc, $invariant, $dateStyles).UtcDateTime
    $endUtc = [datetimeoffset]::Parse(
        $phase.endedAtUtc, $invariant, $dateStyles).UtcDateTime
    $peaks = Get-ResourcePeaks $serverAfter $startUtc $endUtc
    $successful = [long]$successLine.Groups[2].Value
    $failed = [long]$successLine.Groups[3].Value
    $networkBeforeMs = [double]$networkBefore.metrics.query_execution_operations.avg_elapsed_ms
    $networkAfterMs = [double]$networkAfter.metrics.query_execution_operations.avg_elapsed_ms

    [pscustomobject]@{
        ServiceObjective = $phase.serviceObjective
        Vcores = [int]($phase.serviceObjective -replace '^.*_', '')
        Users = [int]$phase.users
        DurationSeconds = [int]$phase.durationSeconds
        SuccessfulOperations = $successful
        FailedOperations = $failed
        OperationsPerSecond = [Math]::Round($successful / [double]$phase.durationSeconds, 2)
        ClientAverageMs = Convert-ToDouble $successLine.Groups[1].Value
        PeakCpuPercent = [double]$peaks.Cpu
        PeakDataIoPercent = [double]$peaks.DataIo
        PeakLogWritePercent = [double]$peaks.LogWrite
        PeakWorkerPercent = [double]$peaks.Workers
        PeakSessionPercent = [double]$peaks.Sessions
        NetworkBeforeMs = [Math]::Round($networkBeforeMs, 3)
        NetworkAfterMs = [Math]::Round($networkAfterMs, 3)
        NetworkChangePercent = [Math]::Round(
            100.0 * ($networkAfterMs - $networkBeforeMs) / [Math]::Max($networkBeforeMs, 0.001), 2)
        PageIoLatchShWaitDeltaMs =
            (Get-WaitMs $serverAfter 'PAGEIOLATCH_SH') - (Get-WaitMs $serverBefore 'PAGEIOLATCH_SH')
        WriteLogWaitDeltaMs =
            (Get-WaitMs $serverAfter 'WRITELOG') - (Get-WaitMs $serverBefore 'WRITELOG')
        RbioWaitDeltaMs = (Get-RbioWaitMs $serverAfter) - (Get-RbioWaitMs $serverBefore)
        ProcedureServerExecution = @($procedureStats | ForEach-Object {
            [pscustomobject]@{
                Procedure = $_.Procedure
                Executions = $_.Executions
                OperationsPerSecond = [Math]::Round(
                    $_.Executions / [double]$phase.durationSeconds, 2)
                AverageDurationMs = $_.AverageDurationMs
                AverageCpuMs = $_.AverageCpuMs
            }
        })
    }
}

if (-not $summary) { throw 'No completed phases were available to summarize.' }

$jsonPath = Join-Path $RunDirectory 'summary.json'
$csvPath = Join-Path $RunDirectory 'summary.csv'
$htmlPath = Join-Path $RunDirectory 'performance-report.html'

$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$summary |
    Select-Object * -ExcludeProperty ProcedureServerExecution |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8

$maxOps = ($summary | Measure-Object OperationsPerSecond -Maximum).Maximum
$maxClient = ($summary | Measure-Object ClientAverageMs -Maximum).Maximum
$throughputBars = foreach ($row in $summary) {
    $width = [Math]::Round(100 * $row.OperationsPerSecond / [Math]::Max($maxOps, 0.01), 1)
    "<div class='bar-row'><span>$($row.Vcores) vCores / $($row.Users) users</span><div class='track'><div class='bar throughput' style='width:${width}%'></div></div><strong>$($row.OperationsPerSecond) ops/s</strong></div>"
}
$latencyBars = foreach ($row in $summary) {
    $width = [Math]::Round(100 * $row.ClientAverageMs / [Math]::Max($maxClient, 0.01), 1)
    "<div class='bar-row'><span>$($row.Vcores) vCores / $($row.Users) users</span><div class='track'><div class='bar latency' style='width:${width}%'></div></div><strong>$($row.ClientAverageMs) ms</strong></div>"
}
$cpuBars = foreach ($row in $summary) {
    $width = [Math]::Min(100, [Math]::Round($row.PeakCpuPercent, 1))
    "<div class='bar-row'><span>$($row.Vcores) vCores / $($row.Users) users</span><div class='track'><div class='bar cpu' style='width:${width}%'></div></div><strong>$($row.PeakCpuPercent)%</strong></div>"
}
$tableRows = foreach ($row in $summary) {
    $networkState = if ([Math]::Abs($row.NetworkChangePercent) -gt 25) { 'unstable' } else { 'stable' }
    "<tr><td>$($row.ServiceObjective)</td><td>$($row.Users)</td><td>$($row.OperationsPerSecond)</td><td>$($row.ClientAverageMs)</td><td>$($row.PeakCpuPercent)%</td><td>$($row.PeakWorkerPercent)%</td><td>$($row.FailedOperations)</td><td>$networkState ($($row.NetworkChangePercent)%)</td></tr>"
}
$procedureNames = @(
    'clinical.GetPatientChart',
    'clinical.RecordVitals',
    'clinical.PlaceMedicationOrder',
    'clinical.FileLabResult',
    'clinical.AddClinicalNote'
)
$procedureRows = foreach ($procedureName in $procedureNames) {
    $cells = foreach ($row in $summary) {
        $procedure = $row.ProcedureServerExecution |
            Where-Object Procedure -eq $procedureName
        "<td>$($procedure.OperationsPerSecond)</td>"
    }
    "<tr><td>$($procedureName -replace '^clinical\.', '')</td>$($cells -join '')</tr>"
}
$procedureHeaders = foreach ($row in $summary) {
    "<th>$($row.Vcores) vCores<br><span>$($row.Users) users</span></th>"
}

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>
  (() => {
    const param = new URLSearchParams(window.location.search).get("scoutTheme");
    const theme =
      param || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    document.documentElement.setAttribute("data-theme", theme);
  })();
</script>
<style>
:root {
  color-scheme: light;
  --cp-bg: #f7f4ef;
  --cp-bg-elevated: #fcfbf8;
  --cp-surface: #ffffff;
  --cp-surface-soft: #f5f5f5;
  --cp-border: #dedede;
  --cp-border-strong: #919191;
  --cp-text: #242424;
  --cp-text-muted: #5c5c5c;
  --cp-text-soft: #6f6f6f;
  --cp-accent: #b11f4b;
  --cp-accent-hover: #9a1a41;
  --cp-accent-soft: rgba(177, 31, 75, 0.08);
  --cp-accent-fg: #ffffff;
  --cp-success: #16a34a;
  --cp-danger: #dc2626;
  --cp-warning: #f59e0b;
  --cp-link: #0078d4;
  --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.12);
  --cp-overlay: rgba(255, 255, 255, 0.8);
  --cp-panel: rgba(255, 255, 255, 0.86);
  --cp-panel-strong: rgba(255, 255, 255, 0.96);
  --cp-sheen: rgba(255, 255, 255, 0.55);
  --cp-highlight: rgba(177, 31, 75, 0.12);
}
html[data-theme="dark"] {
  color-scheme: dark;
  --cp-bg: #3d3b3a;
  --cp-bg-elevated: #343231;
  --cp-surface: #292929;
  --cp-surface-soft: #2e2e2e;
  --cp-border: #474747;
  --cp-border-strong: #5f5f5f;
  --cp-text: #dedede;
  --cp-text-muted: #919191;
  --cp-text-soft: #b0b0b0;
  --cp-accent: #fd8ea1;
  --cp-accent-hover: #fb7b91;
  --cp-accent-soft: rgba(253, 142, 161, 0.14);
  --cp-accent-fg: #1a1a1a;
  --cp-success: #4ade80;
  --cp-danger: #f87171;
  --cp-warning: #fbbf24;
  --cp-link: #4da6ff;
  --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.32);
  --cp-overlay: rgba(41, 41, 41, 0.88);
  --cp-panel: rgba(41, 41, 41, 0.72);
  --cp-panel-strong: rgba(41, 41, 41, 0.96);
  --cp-sheen: rgba(255, 255, 255, 0.04);
  --cp-highlight: rgba(253, 142, 161, 0.12);
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--cp-bg); color: var(--cp-text); font-family: "Segoe UI", Aptos, Calibri, -apple-system, BlinkMacSystemFont, sans-serif; }
main { width: min(1560px, calc(100vw - 32px)); margin: 0 auto; padding: 18px 0 24px; }
header { margin-bottom: 14px; }
h1 { max-width: 720px; font-size: 28px; line-height: 1.15; margin: 0 0 6px; letter-spacing: 0; }
.subtitle { color: var(--cp-text-muted); font-size: 14px; line-height: 1.4; }
.grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; }
.panel { background: var(--cp-surface); border: 1px solid var(--cp-border); border-radius: 8px; padding: 16px; box-shadow: 0 0 2px var(--cp-border); }
.panel h2 { font-size: 16px; margin: 0 0 14px; letter-spacing: 0; }
.bar-row { display: grid; grid-template-columns: 116px minmax(80px, 1fr) 72px; gap: 8px; align-items: center; margin: 10px 0; font-size: 12px; }
.track { height: 14px; background: var(--cp-surface-soft); border: 1px solid var(--cp-border); border-radius: 4px; overflow: hidden; }
.bar { height: 100%; min-width: 2px; }
.throughput { background: var(--cp-accent); }
.latency { background: var(--cp-link); }
.cpu { background: var(--cp-warning); }
strong { text-align: right; }
.evidence { margin-top: 12px; }
.evidence-grid { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, 0.75fr); gap: 12px; }
.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; background: transparent; font-size: 13px; }
th, td { padding: 9px 10px; border-bottom: 1px solid var(--cp-border); text-align: right; white-space: nowrap; }
th:first-child, td:first-child { text-align: left; }
th { color: var(--cp-text-muted); font-weight: 600; }
th span { font-size: 11px; font-weight: 400; }
tbody tr:last-child td { border-bottom: 0; }
.note { color: var(--cp-text-muted); font-size: 13px; margin-top: 16px; }
.server-table td:not(:first-child), .server-table th:not(:first-child) { text-align: center; }
@media (max-width: 1200px) { .evidence-grid { grid-template-columns: 1fr; } }
@media (max-width: 900px) { main { width: min(100% - 24px, 760px); } .grid { grid-template-columns: 1fr; } .bar-row { grid-template-columns: 150px minmax(120px, 1fr) 80px; } }
@media (max-width: 560px) { main { width: calc(100% - 24px); padding: 20px 0 28px; } h1 { font-size: 24px; } .bar-row { grid-template-columns: 1fr; gap: 5px; } strong { text-align: left; } }
</style>
<title>Ward General compute scaling</title>
</head>
<body>
<main>
    <header>
        <h1>Ward General compute scaling</h1>
        <div class="subtitle">Run $($metadata.runId) · $($metadata.database) · proportional user growth</div>
    </header>
  <div class="grid">
    <section class="panel"><h2>Throughput</h2>$($throughputBars -join "`n")</section>
    <section class="panel"><h2>Client latency</h2>$($latencyBars -join "`n")</section>
    <section class="panel"><h2>Peak database CPU</h2>$($cpuBars -join "`n")</section>
  </div>
    <div class="evidence-grid">
    <section class="panel evidence">
    <h2>Phase evidence</h2>
        <div class="table-wrap"><table><thead><tr><th>SLO</th><th>Users</th><th>Ops/s</th><th>Client ms</th><th>Peak CPU</th><th>Peak workers</th><th>Failures</th><th>Network control</th></tr></thead>
        <tbody>$($tableRows -join "`n")</tbody></table></div>
    <p class="note">Client latency includes the laptop, ODBC, network, gateway, result transfer, and server. Server timing and resource metrics support the compute-scaling claim. A network-control change above 25% invalidates laptop-latency comparison for that phase.</p>
  </section>
    <section class="panel evidence">
        <h2>Workload throughput (operations/sec)</h2>
        <div class="table-wrap"><table class="server-table"><thead><tr><th>Stored procedure</th>$($procedureHeaders -join '')</tr></thead>
        <tbody>$($procedureRows -join "`n")</tbody></table></div>
        <p class="note">Calculated from phase-specific Query Store execution-count deltas over each 90-second interval. Raw average CPU and duration remain in summary.json for diagnosis.</p>
    </section>
    </div>
</main>
</body>
</html>
"@

$html | Set-Content -LiteralPath $htmlPath -Encoding utf8

Write-Host 'Stage 1 comparison report created.' -ForegroundColor Green
Write-Host ("  JSON  {0}" -f $jsonPath)
Write-Host ("  CSV   {0}" -f $csvPath)
Write-Host ("  HTML  {0}" -f $htmlPath)
