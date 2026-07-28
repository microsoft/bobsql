<#
.SYNOPSIS
    Generate an interactive HTML chart from sqlsim -querystats -json output.

.DESCRIPTION
    Parses JSON output from sqlsim with -querystats and generates a professional
    HTML report with interactive Chart.js bar charts showing per-query performance.

    Can run sqlsim directly or accept saved JSON file input.
    Opens the HTML report in your default browser automatically.

.PARAMETER JsonFile
    Path to a JSON file containing sqlsim output (from -json -querystats -o).

.PARAMETER ServerName
    Server name for running sqlsim directly (default: localhost).

.PARAMETER DatabaseName
    Database name for running sqlsim directly.

.PARAMETER SqlFile
    SQL script file to run with sqlsim.

.PARAMETER WorkloadFile
    Workload JSON definition file to run with sqlsim.

.PARAMETER Query
    Ad-hoc query to run with sqlsim.

.PARAMETER Threads
    Number of threads (default: 1).

.PARAMETER Iterations
    Iterations per thread (default: 1).

.PARAMETER OutputFile
    Path for the HTML output file (default: querystats-report.html in current directory).

.PARAMETER NoOpen
    Don't automatically open the HTML file in the browser.

.EXAMPLE
    # Run sqlsim and generate chart
    .\querystats-chart.ps1 -SqlFile examples\sql\01-simple-queries.sql -Threads 2 -Iterations 3

.EXAMPLE
    # Chart from saved JSON file
    sqlsim.exe -S localhost -E -i queries.sql -querystats -json -o results.json
    .\querystats-chart.ps1 -JsonFile results.json

.EXAMPLE
    # Chart a workload file
    .\querystats-chart.ps1 -WorkloadFile examples\workload\workload-test.json

.EXAMPLE
    # Save to specific location without opening
    .\querystats-chart.ps1 -WorkloadFile examples\workload\workload-test.json -OutputFile C:\reports\stats.html -NoOpen
#>

param(
    [string]$JsonFile,
    [string]$ServerName = "localhost",
    [string]$DatabaseName,
    [string]$SqlFile,
    [string]$WorkloadFile,
    [string]$Query,
    [int]$Threads = 1,
    [int]$Iterations = 1,
    [string]$OutputFile = "querystats-report.html",
    [switch]$NoOpen
)

# --- Get JSON Data ---

Write-Host "sqlsim Query Stats Chart Generator" -ForegroundColor Cyan
Write-Host ""

$jsonText = $null

if ($JsonFile) {
    if (-not (Test-Path $JsonFile)) {
        Write-Host "Error: File not found: $JsonFile" -ForegroundColor Red
        exit 1
    }
    $jsonText = Get-Content $JsonFile -Raw
    Write-Host "Reading JSON from: $JsonFile" -ForegroundColor Gray

} elseif ($SqlFile -or $WorkloadFile -or $Query) {
    # Run sqlsim directly
    $sqlsimPath = Join-Path $PSScriptRoot "..\..\build\x64\Release\sqlsim.exe"
    if (-not (Test-Path $sqlsimPath)) {
        $sqlsimPath = "sqlsim.exe"
    }

    # Run from workspace root so workload file paths resolve correctly
    $workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    Push-Location $workspaceRoot

    $sqlsimArgs = @("-S", $ServerName, "-E", "-querystats", "-json", "-q")
    if ($DatabaseName) { $sqlsimArgs += @("-d", $DatabaseName) }

    if ($WorkloadFile) {
        $sqlsimArgs += @("-workload", $WorkloadFile)
        Write-Host "Running: sqlsim -workload $WorkloadFile -querystats -json -q" -ForegroundColor Gray
    } elseif ($SqlFile) {
        $sqlsimArgs += @("-i", $SqlFile, "-n", $Threads, "-r", $Iterations)
        Write-Host "Running: sqlsim -i $SqlFile -n $Threads -r $Iterations -querystats -json -q" -ForegroundColor Gray
    } elseif ($Query) {
        $sqlsimArgs += @("-Q", $Query, "-n", $Threads, "-r", $Iterations)
        Write-Host "Running: sqlsim -Q `"$Query`" -n $Threads -r $Iterations -querystats -json -q" -ForegroundColor Gray
    }

    Write-Host ""
    $jsonText = & $sqlsimPath @sqlsimArgs 2>$null | Out-String
    Pop-Location

} else {
    Write-Host "Usage: Provide -JsonFile, -SqlFile, -WorkloadFile, or -Query." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Gray
    Write-Host "  .\querystats-chart.ps1 -SqlFile examples\sql\01-simple-queries.sql -Threads 2 -Iterations 3" -ForegroundColor Gray
    Write-Host "  .\querystats-chart.ps1 -WorkloadFile examples\workload\workload-test.json" -ForegroundColor Gray
    Write-Host "  .\querystats-chart.ps1 -JsonFile results.json" -ForegroundColor Gray
    Write-Host "  .\querystats-chart.ps1 -Query `"SELECT * FROM sys.databases`" -Threads 5 -Iterations 10" -ForegroundColor Gray
    exit 1
}

# --- Parse JSON ---

try {
    $data = $jsonText | ConvertFrom-Json
} catch {
    Write-Host "Error: Failed to parse JSON output" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkRed
    exit 1
}

if (-not $data.query_stats) {
    Write-Host "Error: No query_stats found in JSON output." -ForegroundColor Red
    Write-Host "Make sure you used -querystats flag with sqlsim." -ForegroundColor Yellow
    exit 1
}

$queries = $data.query_stats.queries
$totals = $data.query_stats.totals

if (-not $queries -or $queries.Count -eq 0) {
    Write-Host "No query statistics collected." -ForegroundColor Yellow
    exit 0
}

# --- Build Data Arrays for JavaScript ---

$queryLabels = @()
$queryFullTexts = @()
for ($i = 0; $i -lt $queries.Count; $i++) {
    $preview = ($queries[$i].query -replace '\r?\n', ' ' -replace '\s+', ' ').Trim()
    if ($preview.Length -gt 80) { $preview = $preview.Substring(0, 77) + "..." }
    $queryLabels += "Q$($i+1)"
    $queryFullTexts += $preview
}

$labelsJson = ($queryLabels | ForEach-Object { "`"$_`"" }) -join ", "
$fullLabelsJson = ($queryFullTexts | ForEach-Object { 
    $escaped = $_ -replace '\\', '\\\\' -replace '"', '\"'
    "`"$escaped`""
}) -join ", "

# Metric arrays
$totalElapsedAvg = ($queries | ForEach-Object { $_.total_elapsed_ms.avg }) -join ", "
$totalElapsedMin = ($queries | ForEach-Object { $_.total_elapsed_ms.min }) -join ", "
$totalElapsedMax = ($queries | ForEach-Object { $_.total_elapsed_ms.max }) -join ", "

$serverElapsedAvg = ($queries | ForEach-Object { $_.server_elapsed_ms.avg }) -join ", "
$serverElapsedMin = ($queries | ForEach-Object { $_.server_elapsed_ms.min }) -join ", "
$serverElapsedMax = ($queries | ForEach-Object { $_.server_elapsed_ms.max }) -join ", "

$serverCpuAvg = ($queries | ForEach-Object { $_.server_cpu_ms.avg }) -join ", "
$serverCpuMin = ($queries | ForEach-Object { $_.server_cpu_ms.min }) -join ", "
$serverCpuMax = ($queries | ForEach-Object { $_.server_cpu_ms.max }) -join ", "

$logicalReadsAvg = ($queries | ForEach-Object { $_.logical_reads.avg }) -join ", "
$logicalReadsMin = ($queries | ForEach-Object { $_.logical_reads.min }) -join ", "
$logicalReadsMax = ($queries | ForEach-Object { $_.logical_reads.max }) -join ", "

$physicalReadsAvg = ($queries | ForEach-Object { $_.physical_reads.avg }) -join ", "
$physicalReadsMin = ($queries | ForEach-Object { $_.physical_reads.min }) -join ", "
$physicalReadsMax = ($queries | ForEach-Object { $_.physical_reads.max }) -join ", "

$readAheadReadsAvg = ($queries | ForEach-Object { if ($_.read_ahead_reads) { $_.read_ahead_reads.avg } else { 0 } }) -join ", "
$readAheadReadsMin = ($queries | ForEach-Object { if ($_.read_ahead_reads) { $_.read_ahead_reads.min } else { 0 } }) -join ", "
$readAheadReadsMax = ($queries | ForEach-Object { if ($_.read_ahead_reads) { $_.read_ahead_reads.max } else { 0 } }) -join ", "

$executionCounts = ($queries | ForEach-Object { $_.executions }) -join ", "
$failureCounts = ($queries | ForEach-Object { if ($_.failures) { $_.failures } else { 0 } }) -join ", "

# Configuration values
$server = $data.configuration.server
$database = $data.configuration.database
$isWorkloadMode = $null -ne $data.configuration.workload_groups
$cfgThreads = if ($isWorkloadMode) { "&lt;various&gt;" } else { $data.configuration.threads }
$cfgIterations = if ($isWorkloadMode) { "&lt;various&gt;" } else { $data.configuration.iterations_per_thread }
$authMethod = $data.configuration.authentication
$runtime = $data.metrics.total_runtime_seconds
# Use execution_elapsed_seconds (excludes connection phase) for throughput if available
$execRuntime = if ($data.execution_elapsed_seconds) { $data.execution_elapsed_seconds } else { $runtime }
$throughputTotal = if ($execRuntime -gt 0) { "{0:N1}" -f ($totals.executions / $execRuntime) } else { "--" }
$peakThroughputValue = if ($data.peak_throughput) { "{0:N1}" -f $data.peak_throughput } else { $null }
$avgConnTimeMs = if ($data.connection_stats -and $data.connection_stats.count -gt 0) { "{0:N1}" -f $data.connection_stats.avg_ms } else { $null }

# Throughput per query (exec/s) = 1000 / avg total elapsed ms
# Note: min throughput = 1000 / max elapsed (inverted relationship)
$throughputPerQuery = ($queries | ForEach-Object {
    if ($_.total_elapsed_ms.avg -gt 0) { [math]::Round(1000 / $_.total_elapsed_ms.avg, 2) } else { 0 }
}) -join ", "
$throughputMin = ($queries | ForEach-Object {
    if ($_.total_elapsed_ms.max -gt 0) { [math]::Round(1000 / $_.total_elapsed_ms.max, 2) } else { 0 }
}) -join ", "
$throughputMax = ($queries | ForEach-Object {
    if ($_.total_elapsed_ms.min -gt 0) { [math]::Round(1000 / $_.total_elapsed_ms.min, 2) } else { 0 }
}) -join ", "
$success = $data.success
$errorCount = if ($data.metrics.errors) { $data.metrics.errors.total } else { 0 }
$warningCount = if ($data.metrics.warnings) { $data.metrics.warnings.total } else { 0 }
$errorList = if ($data.metrics.errors -and $data.metrics.errors.list) { $data.metrics.errors.list } else { @() }
$warningList = if ($data.metrics.warnings -and $data.metrics.warnings.list) { $data.metrics.warnings.list } else { @() }
$timestamp = $data.start_time
$endTime = $data.metrics.end_time
$workloadFile = $data.configuration.workload_file
$workloadGroups = $data.configuration.workload_groups

# Query details table
$queryDetailsHtml = ""
for ($i = 0; $i -lt $queries.Count; $i++) {
    $q = $queries[$i]
    $queryText = ($q.query -replace '\r?\n', ' ' -replace '\s+', ' ').Trim()
    $encodedText = [System.Net.WebUtility]::HtmlEncode($queryText)
    $failCount = if ($q.failures) { $q.failures } else { 0 }
    $failCell = if ($failCount -gt 0) { "<td class=`"num color-red`">$failCount</td>" } else { "<td class=`"num`">0</td>" }
    $queryDetailsHtml += @"
<tr id="query-$($i+1)">
    <td class="query-num">Q$($i+1)</td>
    <td class="query-text" title="$encodedText">$encodedText</td>
    <td class="num">$($q.executions)</td>
    $failCell
    <td class="num">$("{0:N3}" -f $q.total_elapsed_ms.avg)</td>
    <td class="num">$("{0:N3}" -f $q.server_elapsed_ms.avg)</td>
    <td class="num">$("{0:N3}" -f $q.server_cpu_ms.avg)</td>
    <td class="num">$("{0:N1}" -f $q.logical_reads.avg)</td>
    <td class="num">$("{0:N1}" -f $q.physical_reads.avg)</td>
    <td class="num">$("{0:N1}" -f $(if ($q.read_ahead_reads) { $q.read_ahead_reads.avg } else { 0 }))</td>
    <td class="num">$("{0:N1}" -f $(if ($q.row_count) { $q.row_count.avg } else { 0 }))</td>
</tr>
"@
}

# Badge class
if ($errorCount -gt 0 -and $warningCount -gt 0) {
    $badgeClass = "badge-error"
    $badgeText = "ERRORS: $errorCount | WARNINGS: $warningCount"
} elseif ($errorCount -gt 0) {
    $badgeClass = "badge-error"
    $badgeText = "ERRORS: $errorCount"
} elseif ($warningCount -gt 0) {
    $badgeClass = "badge-warning"
    $badgeText = "WARNINGS: $warningCount"
} else {
    $badgeClass = "badge-success"
    $badgeText = "SUCCESS"
}
$workloadCard = if ($workloadFile) { "<span><span class='cfg-label'>Workload</span>$([System.Net.WebUtility]::HtmlEncode($workloadFile))</span>" } else { "" }

# Build error/warning alert HTML
$queries = if ($data.query_stats -and $data.query_stats.queries) { $data.query_stats.queries } else { @() }
$alertHtml = ""
if ($errorCount -gt 0) {
    $errorRows = ""
    foreach ($err in $errorList) {
        $ts = if ($err.timestamp) { [System.Net.WebUtility]::HtmlEncode($err.timestamp) } else { "" }
        # Match query text to query_stats index for Q# display
        $qId = ""
        $qNum = 0
        if ($err.query) {
            $errQueryClean = ($err.query -replace '\r?\n', ' ') -replace '\s+', ' '
            for ($qi = 0; $qi -lt $queries.Count; $qi++) {
                $statsQueryClean = ($queries[$qi].query -replace '\r?\n', ' ') -replace '\s+', ' '
                if ($statsQueryClean.Trim() -eq $errQueryClean.Trim()) {
                    $qId = "Q$($qi + 1)"
                    $qNum = $qi + 1
                    break
                }
            }
            if (-not $qId) {
                # Truncate for display
                $preview = $errQueryClean
                if ($preview.Length -gt 60) { $preview = $preview.Substring(0, 60) + "..." }
                $qId = [System.Net.WebUtility]::HtmlEncode($preview)
            }
        }
        $msg = [System.Net.WebUtility]::HtmlEncode($err.message)
        if ($qNum -gt 0) {
            $qCell = "<a href='#query-${qNum}' style='color:#bc4c00;font-weight:600;text-decoration:none' onclick=`"var r=document.getElementById('query-${qNum}');if(r){r.style.background='#fff3cd';setTimeout(function(){r.style.background='';},2000);}`">${qId}</a>"
        } else {
            $qCell = $qId
        }
        $errorRows += "            <tr><td class='msg-time'>${ts}</td><td class='query-num'>${qCell}</td><td>${msg}</td></tr>`n"
    }
    $suffix = if ($errorCount -gt $errorList.Count) { " (showing $($errorList.Count) of $errorCount)" } else { "" }
    $alertHtml += @"
    <div class="alert-box alert-error" id="errors-section">
        <h4>Errors: ${errorCount}${suffix}</h4>
        <table class="alert-table">
            <tr><th>Time</th><th>Query</th><th>Error</th></tr>
$errorRows        </table>
    </div>
"@
}
if ($warningCount -gt 0) {
    $warningRows = ""
    foreach ($warn in $warningList) {
        $ts = if ($warn.timestamp) { [System.Net.WebUtility]::HtmlEncode($warn.timestamp) } else { "" }
        $qId = ""
        $qNum = 0
        if ($warn.query) {
            $warnQueryClean = ($warn.query -replace '\r?\n', ' ') -replace '\s+', ' '
            for ($qi = 0; $qi -lt $queries.Count; $qi++) {
                $statsQueryClean = ($queries[$qi].query -replace '\r?\n', ' ') -replace '\s+', ' '
                if ($statsQueryClean.Trim() -eq $warnQueryClean.Trim()) {
                    $qId = "Q$($qi + 1)"
                    $qNum = $qi + 1
                    break
                }
            }
            if (-not $qId) {
                $preview = $warnQueryClean
                if ($preview.Length -gt 60) { $preview = $preview.Substring(0, 60) + "..." }
                $qId = [System.Net.WebUtility]::HtmlEncode($preview)
            }
        }
        $msg = [System.Net.WebUtility]::HtmlEncode($warn.message)
        if ($qNum -gt 0) {
            $qCell = "<a href='#query-${qNum}' style='color:#bc4c00;font-weight:600;text-decoration:none' onclick=`"var r=document.getElementById('query-${qNum}');if(r){r.style.background='#fff3cd';setTimeout(function(){r.style.background='';},2000);}`">${qId}</a>"
        } else {
            $qCell = $qId
        }
        $warningRows += "            <tr><td class='msg-time'>${ts}</td><td class='query-num'>${qCell}</td><td>${msg}</td></tr>`n"
    }
    $suffix = if ($warningCount -gt $warningList.Count) { " (showing $($warningList.Count) of $warningCount)" } else { "" }
    $alertHtml += @"
    <div class="alert-box alert-warning" id="warnings-section">
        <h4>Warnings: ${warningCount}${suffix}</h4>
        <table class="alert-table">
            <tr><th>Time</th><th>Query</th><th>Warning</th></tr>
$warningRows        </table>
    </div>
"@
}
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# --- Load Chart.js for offline embedding ---

$chartJsPath = Join-Path $PSScriptRoot "chart.umd.min.js"
if (-not (Test-Path $chartJsPath)) {
    Write-Host "Error: chart.umd.min.js not found in script directory." -ForegroundColor Red
    Write-Host "Expected at: $chartJsPath" -ForegroundColor DarkRed
    Write-Host "Download it: Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js' -OutFile '$chartJsPath'" -ForegroundColor Yellow
    exit 1
}
$chartJsContent = Get-Content $chartJsPath -Raw

# --- Generate HTML ---

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>sqlsim Query Stats Report</title>
    <script>$chartJsContent</script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
            background: #f6f8fa;
            color: #1f2328;
            padding: 16px;
            line-height: 1.4;
        }
        .container { max-width: 1400px; margin: 0 auto; }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
            padding-bottom: 8px;
            border-bottom: 1px solid #d0d7de;
        }
        .header h1 { font-size: 16px; font-weight: 600; color: #0969da; }
        .header h1 span { color: #656d76; font-weight: 400; font-size: 13px; }
        .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge-success { background: #1a7f37; color: #fff; }
        .badge-warning { background: #d4a017; color: #fff; }
        .badge-error { background: #cf222e; color: #fff; }

        .metrics-bar { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 10px; }
        .metric-card { background: #ffffff; border: 1px solid #d0d7de; border-radius: 6px; padding: 6px 10px; flex: 1; min-width: 120px; }
        .metric-card .label { font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; }
        .metric-card .value { font-size: 18px; font-weight: 700; font-variant-numeric: tabular-nums; }
        .metric-card .unit { font-size: 11px; color: #656d76; font-weight: 400; }
        .color-blue { color: #0969da; }
        .color-purple { color: #8250df; }
        .color-green { color: #1a7f37; }
        .color-teal { color: #0d9488; }
        .color-steel { color: #4a6fa5; }
        .color-red { color: #cf222e; }
        .color-amber { color: #d4a017; }

        .alert-box { border-radius: 6px; padding: 10px 14px; margin-bottom: 10px; font-size: 12px; }
        .alert-error { background: #fef2f2; border: 1px solid #fca5a5; color: #991b1b; }
        .alert-warning { background: #fefce8; border: 1px solid #fde68a; color: #854d0e; }
        .alert-box h4 { margin: 0 0 8px 0; font-size: 13px; }
        .alert-table { width: 100%; border-collapse: collapse; }
        .alert-table th { text-align: left; font-size: 10px; text-transform: uppercase; letter-spacing: 0.5px; padding: 4px 8px; border-bottom: 1px solid rgba(0,0,0,0.15); }
        .alert-table td { padding: 4px 8px; border-bottom: 1px solid rgba(0,0,0,0.08); font-size: 12px; vertical-align: top; }
        .alert-table .msg-time { color: #9ca3af; font-size: 11px; white-space: nowrap; font-family: "Cascadia Code","Consolas",monospace; }
        .alert-table .query-num { color: #bc4c00; font-weight: 600; white-space: nowrap; }

        .info-grid {
            font-size: 11px;
            color: #656d76;
            margin-bottom: 8px;
            padding: 4px 0;
        }
        .info-grid span { margin-right: 14px; }
        .info-grid .cfg-label { font-weight: 600; color: #8b949e; text-transform: uppercase; font-size: 10px; letter-spacing: 0.3px; margin-right: 3px; }

        .section {
            background: #ffffff;
            border: 1px solid #d0d7de;
            border-radius: 6px;
            padding: 14px;
            margin-bottom: 10px;
        }
        .section h3 { font-size: 14px; font-weight: 600; margin-bottom: 10px; color: #1f2328; }

        .chart-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            margin-bottom: 10px;
        }
        @media (max-width: 900px) { .chart-row { grid-template-columns: 1fr; } }

        .chart-box {
            background: #ffffff;
            border: 1px solid #d0d7de;
            border-radius: 6px;
            padding: 12px;
        }
        .chart-box h3 { font-size: 13px; font-weight: 600; margin-bottom: 6px; color: #1f2328; }
        canvas { max-height: 260px; cursor: pointer; }

        .detail-table { width: 100%; border-collapse: collapse; margin-top: 6px; }
        .detail-table th, .detail-table td {
            padding: 6px 10px;
            text-align: left;
            border-bottom: 1px solid #d0d7de;
            font-size: 13px;
        }
        .detail-table th { color: #656d76; font-weight: 600; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; }
        .detail-table td.num { text-align: right; font-family: 'Cascadia Code', 'Consolas', monospace; }
        .detail-table td.query-num { color: #bc4c00; font-weight: 600; width: 40px; }
        .detail-table td.query-text {
            max-width: 400px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            color: #656d76;
            font-size: 12px;
            font-family: 'Cascadia Code', 'Consolas', monospace;
        }
        .detail-table tr:hover { background: #f3f4f6; }
        .detail-table tr.highlight { background: #ddf4ff; transition: background 0.3s; }
        .detail-table tr.highlight-fade { background: transparent; transition: background 1.5s; }

        .workload-groups { margin-top: 12px; }
        .workload-groups h4 { font-size: 13px; color: #656d76; margin-bottom: 6px; }

        .footer {
            margin-top: 16px; padding-top: 10px; border-top: 1px solid #d0d7de;
            color: #656d76; font-size: 12px; text-align: center;
        }
        .footer a { color: #0969da; text-decoration: none; }
    </style>
</head>
<body>
<div class="container">

    <div class="header">
        <div><h1>sqlsim Query Stats Report <span>Start Run: $timestamp$(if ($endTime) { " &mdash; End Run: $endTime" })</span></h1></div>
        <div><span class="badge $badgeClass">$badgeText</span></div>
    </div>

    <div class="info-grid">
        <span><span class="cfg-label">Server</span>$server</span>
        <span><span class="cfg-label">Database</span>$database</span>
        <span><span class="cfg-label">Auth</span>$authMethod</span>
        <span><span class="cfg-label">Threads</span>$cfgThreads</span>
        <span><span class="cfg-label">Iterations</span>$cfgIterations</span>
        <span><span class="cfg-label">Queries</span>$($queries.Count)</span>
        $workloadCard
    </div>

    <div class="metrics-bar">
        <div class="metric-card"><div class="label">Runtime</div><div class="value color-blue">${runtime}<span class="unit">s</span></div></div>
        <div class="metric-card"><div class="label">Executions</div><div class="value color-purple">$($totals.executions)</div></div>
        <div class="metric-card"><div class="label">Throughput</div><div class="value color-green">${throughputTotal}<span class="unit">/s</span></div></div>
$(if ($peakThroughputValue) { "        <div class=`"metric-card`"><div class=`"label`">Peak Throughput</div><div class=`"value color-teal`">${peakThroughputValue}<span class=`"unit`">/s</span></div></div>" })
$(if ($avgConnTimeMs) { "        <div class=`"metric-card`"><div class=`"label`">Avg Connection</div><div class=`"value color-steel`">${avgConnTimeMs}<span class=`"unit`">ms</span></div></div>" })
$(if ($errorCount -gt 0) { "        <a href=`"#errors-section`" style=`"text-decoration:none`"><div class=`"metric-card`"><div class=`"label`">Errors</div><div class=`"value color-red`">${errorCount}</div></div></a>" })
$(if ($warningCount -gt 0) { "        <a href=`"#warnings-section`" style=`"text-decoration:none`"><div class=`"metric-card`"><div class=`"label`">Warnings</div><div class=`"value color-amber`">${warningCount}</div></div></a>" })
    </div>

    <div class="chart-row">
        <div class="chart-box"><h3>Elapsed Time (ms)</h3><canvas id="chartElapsed"></canvas></div>
        <div class="chart-box"><h3>Server CPU Time (ms)</h3><canvas id="chartServerCPU"></canvas></div>
    </div>
    <div class="chart-row">
        <div class="chart-box"><h3>Logical Reads (pages)</h3><canvas id="chartLogicalReads"></canvas></div>
        <div class="chart-box"><h3>Physical I/O (pages)</h3><canvas id="chartPhysicalIO"></canvas></div>
    </div>
    <div class="chart-row">
        <div class="chart-box"><h3>Throughput per Query (exec/s)</h3><canvas id="chartThroughput"></canvas></div>
        <div class="chart-box"><h3>Execution Distribution</h3><canvas id="chartExecutions"></canvas></div>
    </div>

    <div class="section" style="background: linear-gradient(135deg, #f0f4ff 0%, #e8f0fe 100%); border: 2px solid #4a90d9; padding: 16px;">
        <h3 style="color: #1a56db; font-size: 15px; margin-bottom: 12px;">Aggregate Totals</h3>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px;">
            <div style="background: #fff; border-radius: 6px; padding: 10px 14px; border: 1px solid #d0d7de; text-align: center;">
                <div style="font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">Total Elapsed</div>
                <div style="font-size: 18px; font-weight: 700; color: #1a56db; font-family: 'Cascadia Code','Consolas',monospace;">$("{0:N1}" -f $totals.total_elapsed_ms)<span style="font-size: 11px; font-weight: 400; color: #656d76;"> ms</span></div>
            </div>
            <div style="background: #fff; border-radius: 6px; padding: 10px 14px; border: 1px solid #d0d7de; text-align: center;">
                <div style="font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">Server Elapsed</div>
                <div style="font-size: 18px; font-weight: 700; color: #1a7f37; font-family: 'Cascadia Code','Consolas',monospace;">$("{0:N1}" -f $totals.server_elapsed_ms)<span style="font-size: 11px; font-weight: 400; color: #656d76;"> ms</span></div>
            </div>
            <div style="background: #fff; border-radius: 6px; padding: 10px 14px; border: 1px solid #d0d7de; text-align: center;">
                <div style="font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">Server CPU</div>
                <div style="font-size: 18px; font-weight: 700; color: #bc4c00; font-family: 'Cascadia Code','Consolas',monospace;">$("{0:N1}" -f $totals.server_cpu_ms)<span style="font-size: 11px; font-weight: 400; color: #656d76;"> ms</span></div>
            </div>
            <div style="background: #fff; border-radius: 6px; padding: 10px 14px; border: 1px solid #d0d7de; text-align: center;">
                <div style="font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">Logical Reads</div>
                <div style="font-size: 18px; font-weight: 700; color: #8250df; font-family: 'Cascadia Code','Consolas',monospace;">$("{0:N0}" -f $totals.logical_reads)</div>
            </div>
            <div style="background: #fff; border-radius: 6px; padding: 10px 14px; border: 1px solid #d0d7de; text-align: center;">
                <div style="font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">Physical Reads</div>
                <div style="font-size: 18px; font-weight: 700; color: #cf222e; font-family: 'Cascadia Code','Consolas',monospace;">$("{0:N0}" -f $totals.physical_reads)</div>
            </div>
            <div style="background: #fff; border-radius: 6px; padding: 10px 14px; border: 1px solid #d0d7de; text-align: center;">
                <div style="font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">Read-ahead Reads</div>
                <div style="font-size: 18px; font-weight: 700; color: #d97706; font-family: 'Cascadia Code','Consolas',monospace;">$("{0:N0}" -f $(if ($totals.read_ahead_reads) { $totals.read_ahead_reads } else { 0 }))</div>
            </div>
            <div style="background: #fff; border-radius: 6px; padding: 10px 14px; border: 1px solid #d0d7de; text-align: center;">
                <div style="font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">Executions</div>
                <div style="font-size: 18px; font-weight: 700; color: #1f2328; font-family: 'Cascadia Code','Consolas',monospace;">$("{0:N0}" -f $totals.executions)</div>
            </div>
        </div>
    </div>

    <div class="section">
        <h3>Per-Query Detail</h3>
        <table class="detail-table">
            <tr>
                <th>#</th><th>Query</th>
                <th style="text-align:right">Exec</th>
                <th style="text-align:right">Fail</th>
                <th style="text-align:right">Avg Total ms</th>
                <th style="text-align:right">Avg Server ms</th>
                <th style="text-align:right">Avg CPU ms</th>
                <th style="text-align:right">Avg Logical Reads</th>
                <th style="text-align:right">Avg Physical Reads</th>
                <th style="text-align:right">Avg Read-Ahead</th>
                <th style="text-align:right">Avg Rows</th>
            </tr>
            $queryDetailsHtml
        </table>
    </div>

$alertHtml

    <div class="footer">Generated by sqlsim querystats-chart.ps1 &bull; $generatedAt</div>
</div>

<script>
    const labels = [$labelsJson];
    const fullLabels = [$fullLabelsJson];
    const queryFailures = [$failureCounts];

    // Plugin: draw data labels at end of Avg bars (handles stacked charts too)
    const dataLabelsPlugin = {
        id: 'barDataLabels',
        afterDatasetsDraw(chart) {
            if (chart.config.type !== 'bar') return;
            const ctx = chart.ctx;
            ctx.save();
            ctx.font = '10px Segoe UI, sans-serif';
            ctx.textBaseline = 'middle';
            chart.data.datasets.forEach((ds, dsIdx) => {
                if (ds.hidden) return;
                const meta = chart.getDatasetMeta(dsIdx);
                if (!meta || meta.hidden) return;
                meta.data.forEach((bar, i) => {
                    const val = ds.data[i];
                    if (val === 0 || val === null || val === undefined) return;
                    const text = val >= 100 ? val.toFixed(0) : val >= 1 ? val.toFixed(1) : val.toFixed(3);
                    const segWidth = Math.abs(bar.x - (bar.base || 0));
                    const textWidth = ctx.measureText(text).width;
                    if (segWidth > textWidth + 8) {
                        ctx.fillStyle = '#ffffff';
                        ctx.textAlign = 'right';
                        ctx.fillText(text, bar.x - 4, bar.y);
                    } else if (dsIdx === chart.data.datasets.length - 1 || chart.data.datasets.slice(dsIdx + 1).every(d => d.hidden || (d.data[i] || 0) === 0)) {
                        ctx.fillStyle = '#656d76';
                        ctx.textAlign = 'left';
                        ctx.fillText(text, bar.x + 4, bar.y);
                    }
                });
            });
            ctx.restore();
        }
    };
    Chart.register(dataLabelsPlugin);

    const chartOpts = (unit) => ({
        indexAxis: 'y',
        responsive: true,
        maintainAspectRatio: true,
        animation: { duration: 800, easing: 'easeOutQuart' },
        onHover: (evt, elements, chart) => {
            chart.canvas.style.cursor = elements.length > 0 ? 'pointer' : 'default';
        },
        plugins: {
            legend: { display: true, position: 'top', labels: { color: '#656d76', font: { size: 11 }, boxWidth: 12, padding: 6 } },
            tooltip: {
                backgroundColor: '#ffffff',
                titleColor: '#1f2328',
                bodyColor: '#656d76',
                borderColor: '#d0d7de',
                borderWidth: 1,
                padding: 8,
                callbacks: {
                    title: (items) => {
                        const idx = items[0].dataIndex;
                        let title = fullLabels[idx];
                        if (typeof queryFailures !== 'undefined' && queryFailures[idx] > 0) {
                            title += ' (' + queryFailures[idx] + ' failed)';
                        }
                        return title;
                    },
                    label: (item) => '  ' + item.dataset.label + ': ' + item.raw.toFixed(3) + ' ' + unit
                }
            }
        },
        scales: {
            x: { grid: { color: '#e1e4e8' }, ticks: { color: '#656d76', font: { size: 11 } } },
            y: { grid: { display: false }, ticks: { color: '#bc4c00', font: { size: 12, weight: 'bold' } } }
        }
    });

    function scrollToQuery(index) {
        const row = document.getElementById('query-' + (index + 1));
        if (!row) return;
        row.scrollIntoView({ behavior: 'smooth', block: 'center' });
        row.classList.remove('highlight-fade');
        row.classList.add('highlight');
        setTimeout(() => { row.classList.remove('highlight'); row.classList.add('highlight-fade'); }, 1500);
    }

    // Add native event listeners for Y-axis label clicks (Chart.js onClick only fires within chartArea, not on axis labels)
    function addYAxisClickListener(chart) {
        const canvas = chart.canvas;
        canvas.addEventListener('click', function(e) {
            const yScale = chart.scales.y;
            if (!yScale) return;
            const rect = canvas.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            // Only handle clicks in the Y-axis label area (left of chart area)
            if (x >= chart.chartArea.left) return;
            const numItems = chart.data.labels.length;
            if (numItems === 0) return;
            let closestIdx = -1, closestDist = Infinity;
            for (let i = 0; i < numItems; i++) {
                const pos = yScale.getPixelForValue(i);
                const dist = Math.abs(y - pos);
                if (dist < closestDist) { closestDist = dist; closestIdx = i; }
            }
            const tickSpacing = numItems > 1 ? Math.abs(yScale.getPixelForValue(1) - yScale.getPixelForValue(0)) : 30;
            if (closestDist < tickSpacing * 0.6 && closestIdx >= 0) scrollToQuery(closestIdx);
        });
        canvas.addEventListener('mousemove', function(e) {
            const yScale = chart.scales.y;
            if (!yScale) return;
            const rect = canvas.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            if (x >= chart.chartArea.left) return; // Let Chart.js handle the chart area cursor
            const numItems = chart.data.labels.length;
            if (numItems === 0) { canvas.style.cursor = 'default'; return; }
            let closestDist = Infinity;
            for (let i = 0; i < numItems; i++) {
                const dist = Math.abs(y - yScale.getPixelForValue(i));
                if (dist < closestDist) closestDist = dist;
            }
            const tickSpacing = numItems > 1 ? Math.abs(yScale.getPixelForValue(1) - yScale.getPixelForValue(0)) : 30;
            canvas.style.cursor = closestDist < tickSpacing * 0.6 ? 'pointer' : 'default';
        });
    }

    function makeBarChart(id, avgData, minData, maxData, color, unit) {
        const alpha = (a) => color.replace(/[\d.]+\)$/, a + ')');
        const opts = chartOpts(unit);
        opts.onClick = (evt, elements) => {
            if (elements.length > 0) scrollToQuery(elements[0].index);
        };
        const c = new Chart(document.getElementById(id), {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [
                    { label: 'Avg', data: avgData, backgroundColor: alpha(0.85), borderRadius: 3, borderSkipped: false },
                    { label: 'Min', data: minData, backgroundColor: alpha(0.35), borderRadius: 3, borderSkipped: false, hidden: true },
                    { label: 'Max', data: maxData, backgroundColor: alpha(0.55), borderRadius: 3, borderSkipped: false, hidden: true }
                ]
            },
            options: opts
        });
        addYAxisClickListener(c);
    }

    // Client overhead per query (total - server, clamped to 0)
    const clientOverhead = [$totalElapsedAvg].map((t, i) => Math.max(0, t - [$serverElapsedAvg][i]));

    // Elapsed Time: stacked chart (Server Elapsed + Client Overhead)
    (function() {
        const serverColor = 'rgba(52, 211, 153, 0.85)';
        const clientColor = 'rgba(56, 189, 248, 0.85)';
        const opts = chartOpts('ms');
        opts.plugins.legend.display = true;
        opts.scales.x.stacked = true;
        opts.scales.y.stacked = true;
        opts.onClick = (evt, elements) => {
            if (elements.length > 0) scrollToQuery(elements[0].index);
        };
        opts.plugins.tooltip.callbacks.label = (item) => {
            return '  ' + item.dataset.label + ': ' + item.raw.toFixed(3) + ' ms';
        };
        opts.plugins.tooltip.callbacks.title = (items) => {
            const idx = items[0].dataIndex;
            let title = fullLabels[idx];
            if (queryFailures[idx] > 0) title += ' (' + queryFailures[idx] + ' failed)';
            return title;
        };

        const c = new Chart(document.getElementById('chartElapsed'), {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [
                    { label: 'Server Elapsed', data: [$serverElapsedAvg], backgroundColor: serverColor, borderRadius: 3, borderSkipped: false },
                    { label: 'Client Overhead', data: clientOverhead, backgroundColor: clientColor, borderRadius: 3, borderSkipped: false }
                ]
            },
            options: opts
        });
        addYAxisClickListener(c);
    })();

    makeBarChart('chartServerCPU',
        [$serverCpuAvg], [$serverCpuMin], [$serverCpuMax],
        'rgba(251, 191, 36, 0.8)', 'ms');

    makeBarChart('chartLogicalReads',
        [$logicalReadsAvg], [$logicalReadsMin], [$logicalReadsMax],
        'rgba(192, 132, 252, 0.8)', 'pages');

    // Physical I/O: stacked chart showing Physical Reads + Read-ahead Reads
    (function() {
        const physAvg = [$physicalReadsAvg];
        const raAvg = [$readAheadReadsAvg];
        const physColor = 'rgba(248, 113, 113, 0.85)';
        const raColor = 'rgba(251, 191, 36, 0.85)';

        const opts = chartOpts('pages');
        opts.plugins.legend.display = true;
        opts.scales.x.stacked = true;
        opts.scales.y.stacked = true;
        opts.onClick = (evt, elements) => {
            if (elements.length > 0) scrollToQuery(elements[0].index);
        };
        // Custom tooltip to show both values
        opts.plugins.tooltip.callbacks.label = (item) => {
            return '  ' + item.dataset.label + ': ' + item.raw.toFixed(1) + ' pages';
        };
        opts.plugins.tooltip.callbacks.title = (items) => {
            const idx = items[0].dataIndex;
            let title = fullLabels[idx];
            if (queryFailures[idx] > 0) title += ' (' + queryFailures[idx] + ' failed)';
            return title;
        };

        const c = new Chart(document.getElementById('chartPhysicalIO'), {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [
                    { label: 'Physical Reads', data: physAvg, backgroundColor: physColor, borderRadius: 3, borderSkipped: false },
                    { label: 'Read-ahead Reads', data: raAvg, backgroundColor: raColor, borderRadius: 3, borderSkipped: false }
                ]
            },
            options: opts
        });
        addYAxisClickListener(c);
    })();

    // Throughput per Query bar chart (exec/s)
    makeBarChart('chartThroughput',
        [$throughputPerQuery], [$throughputMin], [$throughputMax],
        'rgba(96, 165, 250, 0.8)', 'exec/s');

    // Execution doughnut
    const doughnutColors = [
        'rgba(56, 189, 248, 0.75)', 'rgba(52, 211, 153, 0.75)', 'rgba(251, 191, 36, 0.75)',
        'rgba(192, 132, 252, 0.75)', 'rgba(248, 113, 113, 0.75)', 'rgba(96, 165, 250, 0.75)',
        'rgba(74, 222, 128, 0.75)', 'rgba(253, 224, 71, 0.75)', 'rgba(167, 139, 250, 0.75)',
        'rgba(251, 146, 60, 0.75)', 'rgba(244, 114, 182, 0.75)', 'rgba(45, 212, 191, 0.75)'
    ];
    const allExecData = [$executionCounts];
    // Filter out queries with 0 executions (e.g. all-failed queries)
    const execFiltered = [];
    for (let i = 0; i < allExecData.length; i++) {
        if (allExecData[i] > 0) execFiltered.push({ label: labels[i], fullLabel: fullLabels[i], data: allExecData[i], origIndex: i });
    }
    const execLabels = execFiltered.map(e => e.label);
    const execData = execFiltered.map(e => e.data);
    const execTotal = execData.reduce((a, b) => a + b, 0);

    const execChart = new Chart(document.getElementById('chartExecutions'), {
        type: 'doughnut',
        data: {
            labels: execLabels,
            datasets: [{
                data: execData,
                backgroundColor: doughnutColors.slice(0, execLabels.length),
                borderColor: '#ffffff',
                borderWidth: 2
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            animation: { animateRotate: true, duration: 1000 },
            onClick: (evt, elements) => { if (elements.length > 0) scrollToQuery(execFiltered[elements[0].index].origIndex); },
            plugins: {
                legend: {
                    position: 'right',
                    labels: { color: '#656d76', font: { size: 11 }, padding: 6 },
                    onClick: (evt, legendItem, legend) => {
                        const chart = legend.chart;
                        chart.toggleDataVisibility(legendItem.index);
                        chart.update();
                    }
                },
                tooltip: {
                    backgroundColor: '#ffffff',
                    titleColor: '#1f2328',
                    bodyColor: '#656d76',
                    borderColor: '#d0d7de',
                    borderWidth: 1,
                    callbacks: {
                        title: (items) => execFiltered[items[0].dataIndex].fullLabel,
                        label: (item) => '  ' + item.raw + ' executions (' + ((item.raw / execTotal) * 100).toFixed(1) + '%)'
                    }
                }
            }
        }
    });
</script>
</body>
</html>
"@

# --- Write and Open ---

$html | Out-File -FilePath $OutputFile -Encoding utf8
$fullPath = (Resolve-Path $OutputFile).Path

Write-Host "Report generated: $fullPath" -ForegroundColor Green

if (-not $NoOpen) {
    Write-Host "Opening in browser..." -ForegroundColor Gray
    Start-Process $fullPath
}
