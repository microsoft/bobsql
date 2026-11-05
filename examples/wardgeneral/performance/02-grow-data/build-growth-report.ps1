<#
.SYNOPSIS
    Builds JSON, CSV, and HTML evidence for one Demo 2 growth run.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RunDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

function Convert-ToDouble([string] $Value) {
    [double]::Parse($Value, $invariant)
}

function Get-Lines([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing evidence file: $Path"
    }
    @(Get-Content -LiteralPath $Path | Where-Object { $_ -match '^[A-Z]+\|' })
}

function Get-Snapshot([string] $Path) {
    $lines = Get-Lines $Path
    $meta = ($lines | Where-Object { $_.StartsWith('META|') } | Select-Object -First 1) -split '\|'
    if ($meta.Count -lt 7) { throw "Missing or invalid META record in $Path" }

    $tables = @{}
    foreach ($line in $lines | Where-Object { $_.StartsWith('TABLE|') }) {
        $parts = $line -split '\|'
        $tables[$parts[2]] = [pscustomobject]@{
            Rows = [long]$parts[3]
            ReservedGB = Convert-ToDouble $parts[4]
        }
    }

    $io = @{}
    foreach ($line in $lines | Where-Object { $_.StartsWith('IO|') }) {
        $parts = $line -split '\|'
        $io[$parts[2]] = [pscustomobject]@{
            Reads = [long]$parts[3]
            BytesRead = [long]$parts[4]
            ReadStallMs = [long]$parts[5]
            Writes = [long]$parts[6]
            BytesWritten = [long]$parts[7]
            WriteStallMs = [long]$parts[8]
        }
    }

    $waits = @{}
    foreach ($line in $lines | Where-Object { $_.StartsWith('WAIT|') }) {
        $parts = $line -split '\|'
        $waits[$parts[2]] = [pscustomobject]@{
            Tasks = [long]$parts[3]
            WaitMs = [long]$parts[4]
            SignalMs = [long]$parts[5]
        }
    }

    [pscustomobject]@{
        CapturedAtUtc = [datetimeoffset]::Parse($meta[2], $invariant)
        Database = $meta[3]
        ServiceObjective = $meta[4]
        ReservedGB = Convert-ToDouble $meta[5]
        DataFileGB = Convert-ToDouble $meta[6]
        Tables = $tables
        Io = $io
        Waits = $waits
    }
}

function Get-Delta([long] $Before, [long] $After) {
    [Math]::Max(0L, $After - $Before)
}

function Get-WaitDelta([object] $Before, [object] $After, [string] $Name) {
    $beforeMs = if ($Before.Waits.ContainsKey($Name)) { $Before.Waits[$Name].WaitMs } else { 0L }
    $afterMs = if ($After.Waits.ContainsKey($Name)) { $After.Waits[$Name].WaitMs } else { 0L }
    Get-Delta $beforeMs $afterMs
}

$metadataPath = Join-Path $RunDirectory 'run-metadata.json'
if (-not (Test-Path -LiteralPath $metadataPath)) { throw "Missing $metadataPath" }
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$before = Get-Snapshot (Join-Path $RunDirectory 'before.txt')
$after = Get-Snapshot (Join-Path $RunDirectory 'after.txt')
$durationSeconds = ([datetimeoffset]$metadata.endedAtUtc - [datetimeoffset]$metadata.startedAtUtc).TotalSeconds
$growthGB = $after.ReservedGB - $before.ReservedGB
$growthGBPerHour = if ($durationSeconds -gt 0) { $growthGB * 3600.0 / $durationSeconds } else { 0.0 }

$previousCapturedAt = $before.CapturedAtUtc
$previousLogBytesWritten = $before.Io.Log.BytesWritten
$timeline = foreach ($path in Get-ChildItem -LiteralPath (Join-Path $RunDirectory 'timeline') -Filter '*.txt' | Sort-Object Name) {
    $lines = Get-Lines $path.FullName
    $sample = ($lines | Where-Object { $_.StartsWith('SAMPLE|') } | Select-Object -First 1) -split '\|'
    $resource = ($lines | Where-Object { $_.StartsWith('RESOURCE|') } | Select-Object -First 1) -split '\|'
    if ($sample.Count -lt 5 -or $resource.Count -lt 8) { continue }

    $ioRows = @{}
    foreach ($line in $lines | Where-Object { $_.StartsWith('IO|') }) {
        $parts = $line -split '\|'
        $ioRows[$parts[2]] = $parts
    }

    $capturedAt = [datetimeoffset]::Parse($sample[2], $invariant)
    $currentLogBytesWritten = if ($ioRows.ContainsKey('Log')) {
        [long]$ioRows.Log[7]
    }
    else { $previousLogBytesWritten }
    $sampleSeconds = ($capturedAt - $previousCapturedAt).TotalSeconds
    $logThroughputMiBPerSecond = if ($sampleSeconds -gt 0) {
        (Get-Delta $previousLogBytesWritten $currentLogBytesWritten) / 1MB / $sampleSeconds
    }
    else { 0.0 }

    $row = [pscustomobject]@{
        Sample = $sample[1]
        CapturedAtUtc = $sample[2]
        ElapsedMinutes = [Math]::Round(
            ($capturedAt - $before.CapturedAtUtc).TotalMinutes, 2)
        ReservedGB = Convert-ToDouble $sample[3]
        AllocatedDataFileGB = Convert-ToDouble $sample[4]
        GrowthGB = [Math]::Round((Convert-ToDouble $sample[3]) - $before.ReservedGB, 3)
        CpuPercent = Convert-ToDouble $resource[3]
        DataIoPercent = Convert-ToDouble $resource[4]
        LogWritePercent = Convert-ToDouble $resource[5]
        WorkerPercent = Convert-ToDouble $resource[6]
        SessionPercent = Convert-ToDouble $resource[7]
        LogThroughputMiBPerSecond = [Math]::Round($logThroughputMiBPerSecond, 2)
        LogWrittenGB = if ($ioRows.ContainsKey('Log')) {
            [Math]::Round((Get-Delta $before.Io.Log.BytesWritten ([long]$ioRows.Log[7])) / 1GB, 3)
        } else { 0.0 }
    }
    $previousCapturedAt = $capturedAt
    $previousLogBytesWritten = $currentLogBytesWritten
    $row
}

$resourceRows = @($timeline)
$peakCpu = if ($resourceRows) { ($resourceRows | Measure-Object CpuPercent -Maximum).Maximum } else { 0.0 }
$peakDataIo = if ($resourceRows) { ($resourceRows | Measure-Object DataIoPercent -Maximum).Maximum } else { 0.0 }
$peakLogWrite = if ($resourceRows) { ($resourceRows | Measure-Object LogWritePercent -Maximum).Maximum } else { 0.0 }
$averageLogWrite = if ($resourceRows) { ($resourceRows | Measure-Object LogWritePercent -Average).Average } else { 0.0 }
$peakLogThroughput = if ($resourceRows) { ($resourceRows | Measure-Object LogThroughputMiBPerSecond -Maximum).Maximum } else { 0.0 }

$waitNames = @($before.Waits.Keys + $after.Waits.Keys | Sort-Object -Unique)
$waitDeltas = @($waitNames | ForEach-Object {
    $beforeWait = if ($before.Waits.ContainsKey($_)) { $before.Waits[$_] } else { $null }
    $afterWait = if ($after.Waits.ContainsKey($_)) { $after.Waits[$_] } else { $null }
    [pscustomobject]@{
        WaitType = $_
        Tasks = Get-Delta $(if ($beforeWait) { $beforeWait.Tasks } else { 0L }) $(if ($afterWait) { $afterWait.Tasks } else { 0L })
        WaitMs = Get-Delta $(if ($beforeWait) { $beforeWait.WaitMs } else { 0L }) $(if ($afterWait) { $afterWait.WaitMs } else { 0L })
        SignalMs = Get-Delta $(if ($beforeWait) { $beforeWait.SignalMs } else { 0L }) $(if ($afterWait) { $afterWait.SignalMs } else { 0L })
    }
} | Where-Object WaitMs -gt 0 | Sort-Object WaitMs -Descending)
$dominantWait = if ($waitDeltas) { $waitDeltas[0].WaitType } else { 'None observed' }
$rbioWaits = @($waitDeltas | Where-Object WaitType -Like 'RBIO_RG_*')
$rbioWaitTasks = if ($rbioWaits.Count -gt 0) {
    [long](($rbioWaits | Measure-Object Tasks -Sum).Sum)
}
else { 0L }
$rbioWaitMs = if ($rbioWaits.Count -gt 0) {
    [long](($rbioWaits | Measure-Object WaitMs -Sum).Sum)
}
else { 0L }

$logWrites = Get-Delta $before.Io.Log.Writes $after.Io.Log.Writes
$logWriteStallMs = Get-Delta $before.Io.Log.WriteStallMs $after.Io.Log.WriteStallMs
$logBytesWritten = Get-Delta $before.Io.Log.BytesWritten $after.Io.Log.BytesWritten
$summary = [ordered]@{
    RunId = $metadata.runId
    Database = $after.Database
    ServiceObjective = $after.ServiceObjective
    StartedAtUtc = $metadata.startedAtUtc
    EndedAtUtc = $metadata.endedAtUtc
    DurationMinutes = [Math]::Round($durationSeconds / 60.0, 2)
    ReservedGBBefore = $before.ReservedGB
    ReservedGBAfter = $after.ReservedGB
    GrowthGB = [Math]::Round($growthGB, 3)
    GrowthGBPerHour = [Math]::Round($growthGBPerHour, 2)
    DataFileGBBefore = $before.DataFileGB
    DataFileGBAfter = $after.DataFileGB
    PeakCpuPercent = [Math]::Round($peakCpu, 2)
    PeakDataIoPercent = [Math]::Round($peakDataIo, 2)
    PeakLogWritePercent = [Math]::Round($peakLogWrite, 2)
    AverageLogWritePercent = [Math]::Round($averageLogWrite, 2)
    PeakLogThroughputMiBPerSecond = [Math]::Round($peakLogThroughput, 2)
    AverageLogThroughputMiBPerSecond = if ($durationSeconds -gt 0) {
        [Math]::Round($logBytesWritten / 1MB / $durationSeconds, 2)
    } else { 0.0 }
    LogBytesWritten = $logBytesWritten
    LogWrites = $logWrites
    AverageLogWriteLatencyMs = if ($logWrites -gt 0) { [Math]::Round($logWriteStallMs / [double]$logWrites, 3) } else { 0.0 }
    WriteLogWaitMs = Get-WaitDelta $before $after 'WRITELOG'
    RbioWaitTypeCount = $rbioWaits.Count
    RbioWaitTasks = $rbioWaitTasks
    RbioWaitMs = $rbioWaitMs
    DominantWait = $dominantWait
    WorkloadExitCode = $metadata.workloadExitCode
    Waits = $waitDeltas
}

$summaryPath = Join-Path $RunDirectory 'summary.json'
$timelinePath = Join-Path $RunDirectory 'growth-timeline.csv'
$htmlPath = Join-Path $RunDirectory 'performance-report.html'
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8
$timeline | Export-Csv -LiteralPath $timelinePath -NoTypeInformation -Encoding utf8

function Format-GB([long] $Bytes) { '{0:N2}' -f ($Bytes / 1GB) }
function Convert-ToInvariant([double] $Value) {
    $Value.ToString('0.###', $invariant)
}

$chartData = @(
    [pscustomobject]@{
        ElapsedMinutes = 0.0
        ReservedGB = $before.ReservedGB
        AllocatedDataFileGB = $before.DataFileGB
    }
    $timeline | ForEach-Object {
        [pscustomobject]@{
            ElapsedMinutes = [double]$_.ElapsedMinutes
            ReservedGB = [double]$_.ReservedGB
            AllocatedDataFileGB = [double]$_.AllocatedDataFileGB
        }
    }
    [pscustomobject]@{
        ElapsedMinutes = [Math]::Round($durationSeconds / 60.0, 2)
        ReservedGB = $after.ReservedGB
        AllocatedDataFileGB = $after.DataFileGB
    }
)
$chartWidth = 900.0
$chartHeight = 270.0
$chartLeft = 70.0
$chartRight = 20.0
$chartTop = 18.0
$chartBottom = 45.0
$plotWidth = $chartWidth - $chartLeft - $chartRight
$plotHeight = $chartHeight - $chartTop - $chartBottom
$maxMinutes = [Math]::Max(1.0, ($chartData | Measure-Object ElapsedMinutes -Maximum).Maximum)
$minReservedGB = [Math]::Min(
    ($chartData | Measure-Object ReservedGB -Minimum).Minimum,
    ($chartData | Measure-Object AllocatedDataFileGB -Minimum).Minimum)
$maxReservedGB = [Math]::Max(
    ($chartData | Measure-Object ReservedGB -Maximum).Maximum,
    ($chartData | Measure-Object AllocatedDataFileGB -Maximum).Maximum)
if ($maxReservedGB -le $minReservedGB) { $maxReservedGB = $minReservedGB + 1.0 }
$yPadding = [Math]::Max(1.0, ($maxReservedGB - $minReservedGB) * 0.08)
$chartMinGB = [Math]::Max(0.0, $minReservedGB - $yPadding)
$chartMaxGB = $maxReservedGB + $yPadding

function Get-ChartX([double] $Minutes) {
    $chartLeft + ($Minutes / $maxMinutes) * $plotWidth
}

function Get-ChartY([double] $ReservedGB) {
    $chartTop + (($chartMaxGB - $ReservedGB) / ($chartMaxGB - $chartMinGB)) * $plotHeight
}

$growthPoints = $chartData | ForEach-Object {
    "$(Convert-ToInvariant (Get-ChartX $_.ElapsedMinutes)),$(Convert-ToInvariant (Get-ChartY $_.ReservedGB))"
}
$allocatedStepData = [System.Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $chartData.Count; $index++) {
    $point = $chartData[$index]
    if ($index -gt 0) {
        $previous = $chartData[$index - 1]
        $allocatedStepData.Add([pscustomobject]@{
            ElapsedMinutes = $point.ElapsedMinutes
            AllocatedDataFileGB = $previous.AllocatedDataFileGB
        })
    }
    $allocatedStepData.Add($point)
}
$allocatedPoints = $allocatedStepData | ForEach-Object {
    "$(Convert-ToInvariant (Get-ChartX $_.ElapsedMinutes)),$(Convert-ToInvariant (Get-ChartY $_.AllocatedDataFileGB))"
}
$gridLines = foreach ($index in 0..4) {
    $fraction = $index / 4.0
    $value = $chartMaxGB - ($chartMaxGB - $chartMinGB) * $fraction
    $y = $chartTop + $plotHeight * $fraction
    "<line x1='$chartLeft' y1='$(Convert-ToInvariant $y)' x2='$($chartLeft + $plotWidth)' y2='$(Convert-ToInvariant $y)'/><text x='$($chartLeft - 10)' y='$(Convert-ToInvariant ($y + 4))' text-anchor='end'>$([Math]::Round($value,1))</text>"
}
$xLabels = foreach ($index in 0..4) {
    $fraction = $index / 4.0
    $minutes = $maxMinutes * $fraction
    $x = $chartLeft + $plotWidth * $fraction
    "<text x='$(Convert-ToInvariant $x)' y='$($chartTop + $plotHeight + 25)' text-anchor='middle'>$([Math]::Round($minutes,1))</text>"
}
$growthChart = @"
<div class="line-chart">
<svg viewBox="0 0 $chartWidth $chartHeight" role="img" aria-labelledby="growth-chart-title growth-chart-desc">
    <title id="growth-chart-title">Database growth and automatic storage allocation</title>
    <desc id="growth-chart-desc">Ward General reserved size grows from $($before.ReservedGB) GB to $($after.ReservedGB) GB while allocated data-file size changes from $($before.DataFileGB) GB to $($after.DataFileGB) GB.</desc>
  <g class="chart-grid">$($gridLines -join '')</g>
    <g class="chart-labels">$($xLabels -join '')<text x="18" y="$($chartTop + $plotHeight / 2)" text-anchor="middle" transform="rotate(-90 18 $($chartTop + $plotHeight / 2))">Database size (GB)</text><text x="$($chartLeft + $plotWidth / 2)" y="$($chartHeight - 4)" text-anchor="middle">Elapsed minutes</text></g>
  <polyline class="growth-line" points="$($growthPoints -join ' ')"/>
    <polyline class="allocation-line" points="$($allocatedPoints -join ' ')"/>
  <circle class="endpoint" cx="$(Convert-ToInvariant (Get-ChartX 0))" cy="$(Convert-ToInvariant (Get-ChartY $before.ReservedGB))" r="5"/>
  <circle class="endpoint" cx="$(Convert-ToInvariant (Get-ChartX ($durationSeconds / 60.0)))" cy="$(Convert-ToInvariant (Get-ChartY $after.ReservedGB))" r="5"/>
</svg>
<div class="legend"><span><i class="growth-key"></i>Reserved size</span><span><i class="allocation-key"></i>Allocated data files</span></div>
</div>
"@
$resourceRowsHtml = foreach ($row in $timeline) {
        "<tr><td>$($row.ElapsedMinutes)</td><td>$($row.ReservedGB)</td><td>$($row.AllocatedDataFileGB)</td><td>$($row.GrowthGB)</td><td>$($row.CpuPercent)%</td><td>$($row.DataIoPercent)%</td><td>$($row.LogWritePercent)%</td><td>$($row.LogThroughputMiBPerSecond)</td><td>$($row.LogWrittenGB)</td></tr>"
}
$waitRowsHtml = if ($waitDeltas.Count -gt 0) {
    $waitDeltas | ForEach-Object {
        "<tr><td>$($_.WaitType)</td><td>$('{0:N0}' -f $_.Tasks)</td><td>$('{0:N0}' -f $_.WaitMs)</td><td>$('{0:N0}' -f $_.SignalMs)</td></tr>"
    }
}
else {
    '<tr><td>None observed</td><td>0</td><td>0</td><td>0</td></tr>'
}
$rbioStatus = if ($rbioWaits.Count -gt 0) {
    "$($rbioWaits.Count) type(s), $('{0:N0}' -f $rbioWaitTasks) tasks, $('{0:N0}' -f $rbioWaitMs) ms"
}
else {
    'None observed (0 types, 0 tasks, 0 ms)'
}
$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { color-scheme: light; --bg:#f4f7f5; --surface:#fff; --ink:#17211c; --muted:#59645e; --border:#d7ded9; --green:#087f5b; --blue:#1971c2; --amber:#d97706; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font-family:Aptos,"Segoe UI",sans-serif; }
main { width:min(1500px,calc(100vw - 32px)); margin:0 auto; padding:20px 0 28px; }
h1 { margin:0 0 4px; font-size:30px; letter-spacing:0; }
.subtitle,.note { color:var(--muted); }
.metrics { display:grid; grid-template-columns:repeat(6,minmax(0,1fr)); gap:10px; margin:16px 0; }
.metric,.panel { background:var(--surface); border:1px solid var(--border); border-radius:8px; padding:14px; }
.panel { overflow-x:auto; }
.metric span { display:block; color:var(--muted); font-size:12px; }
.metric strong { display:block; margin-top:4px; font-size:22px; text-align:left; }
.grid { display:grid; grid-template-columns:1fr 1fr; gap:12px; }
.panel { margin-bottom:12px; }
.panel h2 { margin:0 0 10px; font-size:17px; }
.line-chart { width:100%; min-width:520px; aspect-ratio:10/3; }
.line-chart svg { display:block; width:100%; height:100%; overflow:visible; }
.chart-grid line { stroke:var(--border); stroke-width:1; }
.chart-grid text,.chart-labels text { fill:var(--muted); font-size:12px; }
.growth-line { fill:none; stroke:var(--green); stroke-width:4; stroke-linejoin:round; stroke-linecap:round; }
.allocation-line { fill:none; stroke:var(--blue); stroke-width:4; stroke-linejoin:round; stroke-linecap:round; }
.endpoint { fill:var(--surface); stroke:var(--green); stroke-width:4; }
.legend { display:flex; justify-content:center; gap:22px; color:var(--muted); font-size:12px; }
.legend span { display:flex; align-items:center; gap:6px; }
.legend i { width:18px; height:4px; border-radius:2px; }
.growth-key { background:var(--green); }
.allocation-key { background:var(--blue); }
table { width:100%; border-collapse:collapse; font-size:12px; }
th,td { padding:7px 8px; border-bottom:1px solid var(--border); text-align:right; white-space:nowrap; }
th:first-child,td:first-child { text-align:left; }
th { color:var(--muted); }
.headline { border-left:5px solid var(--green); }
@media(max-width:1000px){.metrics{grid-template-columns:repeat(2,1fr)}.grid{grid-template-columns:1fr}}
@media(max-width:560px){main{width:calc(100% - 20px)}h1{font-size:25px}.metrics{grid-template-columns:1fr}}
</style>
<title>Ward General hands-free growth and I/O</title>
</head>
<body><main>
<header><h1>Hands-free growth and I/O</h1><div class="subtitle">Run $($metadata.runId) · $($after.Database) · $($after.ServiceObjective)</div></header>
<section class="panel headline"><strong>$([Math]::Round($growthGB,2)) GB added automatically at $([Math]::Round($growthGBPerHour,2)) GB/hour.</strong> Actual log throughput peaked at $($summary.PeakLogThroughputMiBPerSecond) MiB/s and averaged $($summary.AverageLogThroughputMiBPerSecond) MiB/s.</section>
<div class="metrics">
  <div class="metric"><span>Reserved size</span><strong>$($before.ReservedGB) → $($after.ReservedGB) GB</strong></div>
    <div class="metric"><span>Allocated data files</span><strong>$($before.DataFileGB) → $($after.DataFileGB) GB</strong></div>
    <div class="metric"><span>Peak log throughput</span><strong>$($summary.PeakLogThroughputMiBPerSecond) MiB/s</strong></div>
    <div class="metric"><span>Average log throughput</span><strong>$($summary.AverageLogThroughputMiBPerSecond) MiB/s</strong></div>
    <div class="metric"><span>Average log write latency</span><strong>$($summary.AverageLogWriteLatencyMs) ms</strong></div>
    <div class="metric"><span>Peak log utilization</span><strong>$([Math]::Round($peakLogWrite,2))%</strong></div>
</div>
<section class="panel"><h2>Database growth and automatic storage allocation</h2>$growthChart</section>
<section class="panel"><h2>Wait evidence</h2><table><tbody><tr><td>RBIO governance waits</td><td>$rbioStatus</td></tr><tr><td>Dominant measured wait</td><td>$dominantWait</td></tr><tr><td>WRITELOG wait time</td><td>$('{0:N0}' -f $summary.WriteLogWaitMs) ms</td></tr></tbody></table><table><thead><tr><th>Wait type</th><th>Tasks</th><th>Wait ms</th><th>Signal ms</th></tr></thead><tbody>$($waitRowsHtml -join "`n")</tbody></table></section>
<section class="panel"><h2>Write performance timeline</h2><table><thead><tr><th>Minutes</th><th>Reserved GB</th><th>Allocated GB</th><th>Growth GB</th><th>CPU</th><th>Data I/O</th><th>Log utilization</th><th>Log MiB/s</th><th>Log written GB</th></tr></thead><tbody>$($resourceRowsHtml -join "`n")</tbody></table></section>
<section class="panel"><h2>I/O summary</h2><table><tbody><tr><td>Log bytes written</td><td>$(Format-GB $summary.LogBytesWritten) GB</td></tr><tr><td>Log write operations</td><td>$('{0:N0}' -f $summary.LogWrites)</td></tr><tr><td>Average log write latency</td><td>$($summary.AverageLogWriteLatencyMs) ms</td></tr><tr><td>Workload exit code</td><td>$($summary.WorkloadExitCode)</td></tr></tbody></table></section>
<p class="note">Resource percentages are 15-second database-engine samples. Log throughput is calculated from consecutive virtual-log-file byte-counter deltas divided by elapsed sample time; it is not inferred from the hardware ceiling.</p>
</main></body></html>
"@
$html | Set-Content -LiteralPath $htmlPath -Encoding utf8

Write-Host 'Stage 2 growth report created.' -ForegroundColor Green
Write-Host ("  JSON  {0}" -f $summaryPath)
Write-Host ("  CSV   {0}" -f $timelinePath)
Write-Host ("  HTML  {0}" -f $htmlPath)