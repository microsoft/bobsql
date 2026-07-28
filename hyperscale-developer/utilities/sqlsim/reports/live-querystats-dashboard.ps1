<#
.SYNOPSIS
    Live streaming querystats dashboard for sqlsim.

.DESCRIPTION
    Starts a sqlsim workload with -querystats-interval and serves a live HTML dashboard
    that auto-updates with real-time query performance data using Chart.js.

    The dashboard shows:
    - Per-query performance charts (total elapsed, server elapsed, server CPU, I/O)
    - Live counters for elapsed time, total executions, and throughput
    - Connection statistics
    - Auto-refreshing charts on the configured interval

.PARAMETER ServerName
    SQL Server name (default: localhost).

.PARAMETER DatabaseName
    Database name.

.PARAMETER SqlFile
    SQL script file to run.

.PARAMETER WorkloadFile
    Workload JSON definition file to run.

.PARAMETER Query
    Ad-hoc query to run.

.PARAMETER Threads
    Number of threads (default: 4).

.PARAMETER Iterations
    Iterations per thread (default: 100).

.PARAMETER Interval
    Querystats snapshot interval in seconds (default: 2).

.PARAMETER Port
    HTTP server port (default: 8088).

.PARAMETER NoOpen
    Don't automatically open the browser.

.PARAMETER WorkloadScript
    Workload JSON file with per-query threads/iterations (e.g., mixed-workload-adventureworks.json).
    Same as -WorkloadFile but a more descriptive name for scripted workloads.

.PARAMETER DropCleanBuffers
    Run DBCC DROPCLEANBUFFERS before starting the workload to clear the buffer cache,
    forcing physical reads. Useful for testing I/O behavior.

.EXAMPLE
    # Live dashboard for mixed workload
    .\live-querystats-dashboard.ps1 -SqlFile examples\sql\08-mixed-workload.sql -Threads 8 -Iterations 200

.EXAMPLE
    # Live dashboard for workload JSON with varied threads/iterations per query
    .\live-querystats-dashboard.ps1 -WorkloadScript examples\workload\mixed-workload-adventureworks.json -DatabaseName AdventureWorksLT

.EXAMPLE
    # Live dashboard for workload file
    .\live-querystats-dashboard.ps1 -WorkloadFile examples\workload\workload-test.json

.EXAMPLE
    # Live dashboard on custom port
    .\live-querystats-dashboard.ps1 -SqlFile examples\sql\08-mixed-workload.sql -Port 9090 -Threads 16 -Iterations 500
#>

param(
    [string]$ServerName = "localhost",
    [string]$DatabaseName,
    [string]$SqlFile,
    [string]$WorkloadFile,
    [string]$WorkloadScript,
    [string]$Query,
    [int]$Threads = 4,
    [int]$Iterations = 100,
    [int]$Interval = 2,
    [int]$Port = 8088,
    [switch]$NoOpen,
    [switch]$DropCleanBuffers
)

# --- Validate parameters ---

# -WorkloadScript is an alias for -WorkloadFile
if ($WorkloadScript -and -not $WorkloadFile) {
    $WorkloadFile = $WorkloadScript
}

if (-not $SqlFile -and -not $WorkloadFile -and -not $Query) {
    Write-Host "Usage: Provide -SqlFile, -WorkloadFile, -WorkloadScript, or -Query." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Gray
    Write-Host "  .\live-querystats-dashboard.ps1 -SqlFile examples\sql\08-mixed-workload.sql -Threads 8 -Iterations 200" -ForegroundColor Gray
    Write-Host "  .\live-querystats-dashboard.ps1 -WorkloadScript examples\workload\mixed-workload-adventureworks.json -DatabaseName AdventureWorksLT" -ForegroundColor Gray
    Write-Host "  .\live-querystats-dashboard.ps1 -WorkloadFile examples\workload\workload-test.json" -ForegroundColor Gray
    exit 1
}

# --- Find sqlsim executable ---

$sqlsimPath = Join-Path $PSScriptRoot "..\..\build\x64\Release\sqlsim.exe"
if (-not (Test-Path $sqlsimPath)) {
    $sqlsimPath = "sqlsim.exe"
    if (-not (Get-Command $sqlsimPath -ErrorAction SilentlyContinue)) {
        Write-Host "Error: sqlsim.exe not found. Build first with .\build.ps1" -ForegroundColor Red
        exit 1
    }
}

# --- Load Chart.js ---

$chartJsPath = Join-Path $PSScriptRoot "chart.umd.min.js"
if (-not (Test-Path $chartJsPath)) {
    Write-Host "Error: chart.umd.min.js not found in script directory." -ForegroundColor Red
    exit 1
}
$chartJsContent = Get-Content $chartJsPath -Raw

# --- Setup snapshot file ---

$snapshotFile = Join-Path ([System.IO.Path]::GetTempPath()) "sqlsim-querystats-live.json"

# Clean up any previous snapshot
Remove-Item $snapshotFile -ErrorAction SilentlyContinue

# --- Build sqlsim command ---

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

$sqlsimArgs = @("-S", $ServerName, "-E", "-querystats", "-querystats-interval", "1", "-querystats-file", $snapshotFile, "-q")
if ($DatabaseName) { $sqlsimArgs += @("-d", $DatabaseName) }

$workloadDesc = ""
if ($WorkloadFile) {
    $sqlsimArgs += @("-workload", $WorkloadFile)
    $workloadDesc = "Workload: $WorkloadFile"
} elseif ($SqlFile) {
    $sqlsimArgs += @("-i", $SqlFile, "-n", $Threads, "-r", $Iterations)
    $workloadDesc = "File: $SqlFile | Threads: $Threads | Iterations: $Iterations"
} elseif ($Query) {
    $sqlsimArgs += @("-Q", $Query, "-n", $Threads, "-r", $Iterations)
    $workloadDesc = "Query: $Query | Threads: $Threads | Iterations: $Iterations"
}

Write-Host ""
Write-Host "sqlsim Live Query Stats Dashboard" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Server:    $ServerName" -ForegroundColor White
if ($DatabaseName) { Write-Host "  Database:  $DatabaseName" -ForegroundColor White }
Write-Host "  $workloadDesc" -ForegroundColor White
Write-Host "  Interval:  ${Interval}s" -ForegroundColor White
Write-Host "  Dashboard: http://localhost:$Port/" -ForegroundColor Green
Write-Host ""

# --- Optionally drop clean buffers to force physical reads ---

if ($DropCleanBuffers) {
    Write-Host "Running DBCC DROPCLEANBUFFERS..." -ForegroundColor Gray
    $dbccArgs = @("-S", $ServerName, "-E", "-Q", "DBCC DROPCLEANBUFFERS", "-q")
    if ($DatabaseName) { $dbccArgs += @("-d", $DatabaseName) }
    & $sqlsimPath @dbccArgs 2>$null | Out-Null
    Write-Host "  Buffer cache cleared." -ForegroundColor DarkGray
}

# --- Start sqlsim in background ---

Write-Host "Starting sqlsim..." -ForegroundColor Gray
$sqlsimLogFile = Join-Path ([System.IO.Path]::GetTempPath()) "sqlsim-dashboard.log"
$sqlsimProcess = Start-Process -FilePath $sqlsimPath -ArgumentList $sqlsimArgs -WorkingDirectory $workspaceRoot -PassThru -RedirectStandardOutput $sqlsimLogFile -RedirectStandardError "$sqlsimLogFile.err"

# Give sqlsim a moment to start and create the snapshot file
Start-Sleep -Seconds 1

# --- Build HTML Dashboard ---

$dashboardHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>sqlsim Live Query Stats</title>
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
.badge-error { background: #cf222e; color: #fff; }
.status-badge { padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; text-transform: uppercase; }
.status-running { background: #dafbe1; color: #1a7f37; animation: pulse 1.5s infinite; }
.status-complete { background: #1a7f37; color: #fff; }
.status-error { background: #cf222e; color: #fff; }
.status-warning { background: #d4a017; color: #fff; }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.7; } }

.alert-box { border-radius: 6px; padding: 10px 14px; margin-bottom: 10px; font-size: 12px; }
.alert-box h4 { font-size: 13px; font-weight: 600; margin-bottom: 6px; }
.alert-box ul { margin: 0; padding-left: 18px; }
.alert-box li { margin-bottom: 3px; }
.alert-error { background: #fef2f2; border: 1px solid #fca5a5; color: #991b1b; }
.alert-warning { background: #fefce8; border: 1px solid #fde68a; color: #854d0e; }
.msg-time { font-size: 10px; color: #656d76; margin-right: 6px; font-family: "Cascadia Code","Consolas",monospace; }

.metrics-bar { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 10px; }
.metric-card { background: #ffffff; border: 1px solid #d0d7de; border-radius: 6px; padding: 6px 10px; flex: 1; min-width: 120px; }
.metric-card .label { font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; }
.metric-card .value { font-size: 18px; font-weight: 700; font-variant-numeric: tabular-nums; }
.metric-card .unit { font-size: 11px; color: #656d76; font-weight: 400; }
.color-blue { color: #0969da; }
.color-purple { color: #7C3AED; }
.color-green { color: #059669; }
.color-amber { color: #D97706; }
.color-steel { color: #57606a; }
.color-teal { color: #0d9488; }
.color-yellow { color: #CA8A04; }
.color-red { color: #DC2626; }

.info-grid {
    font-size: 11px;
    color: #656d76;
    margin-bottom: 8px;
    padding: 4px 0;
    display: flex;
    align-items: center;
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

.footer {
    margin-top: 16px; padding-top: 10px; border-top: 1px solid #d0d7de;
    color: #656d76; font-size: 12px; text-align: center;
}
.footer a { color: #0969da; text-decoration: none; }
.no-data { text-align: center; padding: 40px; color: #656d76; font-size: 14px; }
.save-btn { padding: 4px 12px; border-radius: 6px; border: 1px solid #d0d7de; background: #ffffff; color: #0969da; font-size: 11px; font-weight: 600; cursor: pointer; display: none; }
.save-btn:hover { background: #ddf4ff; border-color: #0969da; }
.progress-wrap { display: flex; align-items: center; gap: 6px; }
.progress-track { width: 160px; height: 6px; background: #e1e4e8; border-radius: 3px; overflow: hidden; }
.progress-fill { height: 100%; background: #0969da; border-radius: 3px; transition: width 0.4s ease; }
.progress-text { font-size: 11px; color: #656d76; white-space: nowrap; font-variant-numeric: tabular-nums; }
</style>
</head>
<body>
<div class="container">

    <div class="header">
        <div>
            <h1>sqlsim Query Stats Report <span id="lastUpdate">Waiting for data...</span></h1>
        </div>
        <div style="display:flex;align-items:center;gap:8px;">
            <span id="statusBadge" class="status-badge status-running" style="cursor:pointer" onclick="var el=document.getElementById('alertContainer');if(el&&el.innerHTML)el.scrollIntoView({behavior:'smooth',block:'center'})">STARTING</span>
            <button id="saveBtn" class="save-btn" onclick="saveReport()">Save Report</button>
        </div>
    </div>

    <div class="info-grid" id="configBar">
        <span><span class="cfg-label">Server</span><span id="cfgServer">--</span></span>
        <span><span class="cfg-label">Database</span><span id="cfgDatabase">--</span></span>
        <span><span class="cfg-label">Auth</span><span id="cfgAuth">--</span></span>
        <span><span class="cfg-label">Threads</span><span id="cfgThreads">--</span></span>
        <span><span class="cfg-label">Iterations</span><span id="cfgIterations">--</span></span>
        <span><span class="cfg-label">Queries</span><span id="cfgQueries">--</span></span>
        <div class="progress-wrap" id="progressRow" style="display:none">
            <div class="progress-track"><div class="progress-fill" id="progressFill" style="width:0%"></div></div>
            <span class="progress-text" id="progressText">0%</span>
        </div>
    </div>

    <div class="metrics-bar">
        <div class="metric-card">
            <div class="label">Runtime</div>
            <div class="value color-blue" id="metricElapsed">--<span class="unit">s</span></div>
        </div>
        <div class="metric-card">
            <div class="label">Executions</div>
            <div class="value color-purple" id="metricExecs">--</div>
        </div>
        <div class="metric-card">
            <div class="label">Throughput</div>
            <div class="value color-green" id="metricThroughput">--<span class="unit">/s</span></div>
        </div>
        <div class="metric-card">
            <div class="label">Peak Throughput</div>
            <div class="value color-teal" id="metricPeakThroughput">--<span class="unit">/s</span></div>
        </div>
        <div class="metric-card">
            <div class="label">Avg Connection</div>
            <div class="value color-steel" id="metricConnTime">--<span class="unit">ms</span></div>
        </div>
        <div class="metric-card" id="metricErrorsCard" style="display:none;cursor:pointer" onclick="document.getElementById('alertContainer').scrollIntoView({behavior:'smooth',block:'center'})">
            <div class="label">Errors</div>
            <div class="value color-red" id="metricErrors">0</div>
        </div>
        <div class="metric-card" id="metricWarningsCard" style="display:none;cursor:pointer" onclick="document.getElementById('alertContainer').scrollIntoView({behavior:'smooth',block:'center'})">
            <div class="label">Warnings</div>
            <div class="value color-amber" id="metricWarnings">0</div>
        </div>
    </div>

    <div class="chart-row">
        <div class="chart-box"><h3>Elapsed Time (ms)</h3><canvas id="chartElapsed"></canvas></div>
        <div class="chart-box"><h3>Server CPU Time (ms)</h3><canvas id="chartServerCpu"></canvas></div>
    </div>
    <div class="chart-row">
        <div class="chart-box"><h3>Logical Reads (pages)</h3><canvas id="chartLogicalReads"></canvas></div>
        <div class="chart-box"><h3>Physical I/O (pages)</h3><canvas id="chartPhysicalIO"></canvas></div>
    </div>
    <div class="chart-row">
        <div class="chart-box"><h3>Throughput per Query (exec/s)</h3><canvas id="chartThroughput"></canvas></div>
        <div class="chart-box"><h3>Execution Distribution</h3><canvas id="chartExecutions"></canvas></div>
    </div>

    <div id="aggregateTotals">
        <div style="background:linear-gradient(135deg,#f0f4ff 0%,#e8f0fe 100%);border:2px solid #4a90d9;border-radius:6px;padding:16px;margin-bottom:10px;">
            <h3 style="color:#1a56db;font-size:15px;margin-bottom:12px;">Aggregate Totals</h3>
            <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;">
                <div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;">
                    <div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Total Elapsed</div>
                    <div style="font-size:18px;font-weight:700;color:#1a56db;font-family:'Cascadia Code','Consolas',monospace;"><span data-metric="totalElapsed">--</span><span style="font-size:11px;font-weight:400;color:#656d76;"> ms</span></div>
                </div>
                <div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;">
                    <div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Server Elapsed</div>
                    <div style="font-size:18px;font-weight:700;color:#1a7f37;font-family:'Cascadia Code','Consolas',monospace;"><span data-metric="serverElapsed">--</span><span style="font-size:11px;font-weight:400;color:#656d76;"> ms</span></div>
                </div>
                <div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;">
                    <div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Server CPU</div>
                    <div style="font-size:18px;font-weight:700;color:#bc4c00;font-family:'Cascadia Code','Consolas',monospace;"><span data-metric="serverCpu">--</span><span style="font-size:11px;font-weight:400;color:#656d76;"> ms</span></div>
                </div>
                <div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;">
                    <div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Logical Reads</div>
                    <div style="font-size:18px;font-weight:700;color:#8250df;font-family:'Cascadia Code','Consolas',monospace;"><span data-metric="logicalReads">--</span></div>
                </div>
                <div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;">
                    <div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Physical Reads</div>
                    <div style="font-size:18px;font-weight:700;color:#cf222e;font-family:'Cascadia Code','Consolas',monospace;"><span data-metric="physicalReads">--</span></div>
                </div>
                <div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;">
                    <div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Read-ahead Reads</div>
                    <div style="font-size:18px;font-weight:700;color:#d97706;font-family:'Cascadia Code','Consolas',monospace;"><span data-metric="readAheadReads">--</span></div>
                </div>
                <div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;">
                    <div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Executions</div>
                    <div style="font-size:18px;font-weight:700;color:#1f2328;font-family:'Cascadia Code','Consolas',monospace;"><span data-metric="executions">--</span></div>
                </div>
            </div>
        </div>
    </div>

    <div class="section">
        <h3>Per-Query Detail</h3>
        <div id="detailTableContainer">
            <div class="no-data">Waiting for query data...</div>
        </div>
    </div>

    <div id="alertContainer"></div>

    <div class="footer">Generated by sqlsim Live Dashboard &bull; Polling every ${Interval}s</div>

</div>

<script>
$chartJsContent
</script>
<script>
// --- Chart.js Configuration ---
const POLL_INTERVAL = 1000;  // Poll every 1s for responsive updates (snapshot writes every ${Interval}s)
const CHART_COLORS = {
    totalElapsed: 'rgba(56, 189, 248, 0.85)',    // sky blue
    serverElapsed: 'rgba(52, 211, 153, 0.85)',   // emerald
    serverCpu:     'rgba(251, 191, 36, 0.85)',    // amber
    logicalReads:  'rgba(192, 132, 252, 0.85)',   // light purple
    physicalReads: 'rgba(248, 113, 113, 0.85)',   // red
    readAheadReads: 'rgba(251, 191, 36, 0.85)',   // amber
};

let charts = {};
let lastData = null;
let pollTimer = null;
let pollCount = 0;
let frozenThroughput = null;
let workloadStartTime = null;
let fetchFailCount = 0;
const MAX_FETCH_FAILS = 3;

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

function createChart(canvasId, label, avgColor, unit) {
    const alpha = (a) => avgColor.replace(/[\d.]+\)$/, a + ')');
    const ctx = document.getElementById(canvasId).getContext('2d');
    const c = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: [],
            datasets: [
                { label: 'Avg', data: [], backgroundColor: alpha(0.85), borderRadius: 3, borderSkipped: false },
                { label: 'Min', data: [], backgroundColor: alpha(0.35), borderRadius: 3, borderSkipped: false, hidden: true },
                { label: 'Max', data: [], backgroundColor: alpha(0.55), borderRadius: 3, borderSkipped: false, hidden: true }
            ]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            maintainAspectRatio: true,
            animation: { duration: 400 },
            onHover: function(evt, elements) {
                this.canvas.style.cursor = elements.length > 0 ? 'pointer' : 'default';
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
                        title: function(items) {
                            if (lastData && lastData.query_stats && lastData.query_stats.queries) {
                                const idx = items[0].dataIndex;
                                const q = lastData.query_stats.queries[idx];
                                if (q) {
                                    const text = q.query.replace(/\\n/g, ' ').replace(/\\s+/g, ' ');
                                    const preview = text.length > 80 ? text.substring(0, 77) + '...' : text;
                                    return 'Q' + (idx+1) + ': ' + preview;
                                }
                            }
                            return items[0].label;
                        },
                        label: (item) => '  ' + item.dataset.label + ': ' + item.raw.toFixed(3) + ' ' + unit
                    }
                }
            },
            scales: {
                x: { grid: { color: '#e1e4e8' }, ticks: { color: '#656d76', font: { size: 11 } } },
                y: { grid: { display: false }, ticks: { color: '#bc4c00', font: { size: 12, weight: 'bold' } } }
            },
            onClick: function(evt) {
                const elements = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, false);
                if (elements.length > 0) scrollToQuery(elements[0].index + 1);
            }
        }
    });
    addYAxisClickListener(c, 1);
    return c;
}

// Add native event listeners for Y-axis label clicks
// (Chart.js onClick only fires within chartArea, not on axis labels)
// indexOffset: 0 for 0-based scroll, 1 for 1-based scroll (live dashboard uses 1-based query-N ids)
function addYAxisClickListener(chart, indexOffset) {
    const canvas = chart.canvas;
    canvas.addEventListener('click', function(e) {
        const yScale = chart.scales.y;
        if (!yScale) return;
        const rect = canvas.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
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
        if (closestDist < tickSpacing * 0.6 && closestIdx >= 0) scrollToQuery(closestIdx + indexOffset);
    });
    canvas.addEventListener('mousemove', function(e) {
        const yScale = chart.scales.y;
        if (!yScale) return;
        const rect = canvas.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        if (x >= chart.chartArea.left) return;
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

function scrollToQuery(num) {
    const row = document.getElementById('query-' + num);
    if (row) {
        row.scrollIntoView({ behavior: 'smooth', block: 'center' });
        row.classList.add('highlight');
        setTimeout(() => { row.classList.add('highlight-fade'); row.classList.remove('highlight'); }, 200);
        setTimeout(() => { row.classList.remove('highlight-fade'); }, 2000);
    }
}

function updateChartData(chart, labels, avgData, minData, maxData) {
    chart.data.labels = labels;
    chart.data.datasets[0].data = avgData;
    chart.data.datasets[1].data = minData;
    chart.data.datasets[2].data = maxData;
    chart.update('none');
}

function escapeHtml(str) {
    if (!str) return '';
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function formatNumber(n, decimals) {
    if (n === null || n === undefined) return '--';
    return Number(n).toFixed(decimals || 0);
}

function updateDashboard(data) {
    lastData = data;
    pollCount++;

    // Update status badge - 3-state: errors, warnings, or success
    const badge = document.getElementById('statusBadge');
    const totalErrors = data.total_errors || 0;
    const totalWarnings = data.total_warnings || 0;
    if (data.status === 'complete') {
        if (totalErrors > 0) {
            badge.textContent = 'ERRORS: ' + totalErrors;
            badge.className = 'status-badge status-error';
        } else if (totalWarnings > 0) {
            badge.textContent = 'WARNINGS: ' + totalWarnings;
            badge.className = 'status-badge status-warning';
        } else {
            badge.textContent = 'COMPLETE';
            badge.className = 'status-badge status-complete';
        }
    } else {
        if (totalErrors > 0) {
            badge.textContent = 'RUNNING (ERRORS: ' + totalErrors + ')';
            badge.className = 'status-badge status-error';
        } else {
            badge.textContent = 'RUNNING';
            badge.className = 'status-badge status-running';
        }
    }

    // Update error/warning alerts
    const alertContainer = document.getElementById('alertContainer');
    let alertHtml = '';
    // Build queries array for Q# matching
    const queriesForMatch = (data.query_stats && data.query_stats.queries) ? data.query_stats.queries : [];
    function matchQueryToNum(queryText) {
        if (!queryText) return '';
        const clean = queryText.replace(/\r?\n/g, ' ').replace(/\s+/g, ' ').trim();
        for (let i = 0; i < queriesForMatch.length; i++) {
            const statsClean = (queriesForMatch[i].query || '').replace(/\r?\n/g, ' ').replace(/\s+/g, ' ').trim();
            if (statsClean === clean) return 'Q' + (i + 1);
        }
        return clean.length > 60 ? escapeHtml(clean.substring(0, 60) + '...') : escapeHtml(clean);
    }
    if (totalErrors > 0 && data.recent_errors && data.recent_errors.length > 0) {
        let rows = data.recent_errors.map(e => {
            const ts = e.timestamp ? '<span class="msg-time">' + escapeHtml(e.timestamp) + '</span>' : '';
            const qId = matchQueryToNum(e.query);
            const qCell = qId ? '<span class="query-num" style="color:#bc4c00;font-weight:600">' + qId + '</span> ' : '';
            return '<li>' + ts + qCell + escapeHtml(e.message) + '</li>';
        }).join('');
        const suffix = totalErrors > data.recent_errors.length ? ' (showing ' + data.recent_errors.length + ' of ' + totalErrors + ')' : '';
        alertHtml += '<div class="alert-box alert-error"><h4>Errors: ' + totalErrors + suffix + '</h4><ul>' + rows + '</ul></div>';
    }
    if (totalWarnings > 0 && data.recent_warnings && data.recent_warnings.length > 0) {
        let rows = data.recent_warnings.map(w => {
            const ts = w.timestamp ? '<span class="msg-time">' + escapeHtml(w.timestamp) + '</span>' : '';
            const qId = matchQueryToNum(w.query);
            const qCell = qId ? '<span class="query-num" style="color:#bc4c00;font-weight:600">' + qId + '</span> ' : '';
            return '<li>' + ts + qCell + escapeHtml(w.message) + '</li>';
        }).join('');
        const suffix = totalWarnings > data.recent_warnings.length ? ' (showing ' + data.recent_warnings.length + ' of ' + totalWarnings + ')' : '';
        alertHtml += '<div class="alert-box alert-warning"><h4>Warnings: ' + totalWarnings + suffix + '</h4><ul>' + rows + '</ul></div>';
    }
    alertContainer.innerHTML = alertHtml;

    // Update error/warning metric cards
    const errCard = document.getElementById('metricErrorsCard');
    const warnCard = document.getElementById('metricWarningsCard');
    if (totalErrors > 0) {
        errCard.style.display = '';
        document.getElementById('metricErrors').textContent = totalErrors;
    } else {
        errCard.style.display = 'none';
    }
    if (totalWarnings > 0) {
        warnCard.style.display = '';
        document.getElementById('metricWarnings').textContent = totalWarnings;
    } else {
        warnCard.style.display = 'none';
    }

    // Update metrics bar
    document.getElementById('metricElapsed').innerHTML = formatNumber(data.elapsed_seconds, 1) + '<span class="unit">s</span>';

    const totalExecs = data.query_stats && data.query_stats.totals ? data.query_stats.totals.executions : 0;
    document.getElementById('metricExecs').textContent = totalExecs.toLocaleString();

    // Throughput: total queries completed / execution elapsed seconds (excludes connection phase)
    // Uses execution_elapsed_seconds which measures from first to last query execution
    // Show honest live value while running; freeze only at completion to prevent post-finish decay
    const execElapsed = data.execution_elapsed_seconds || 0;
    let throughput;
    if (frozenThroughput !== null) {
        throughput = frozenThroughput;
    } else {
        throughput = execElapsed > 0 ? (totalExecs / execElapsed) : 0;
        if (data.status === 'complete') {
            frozenThroughput = throughput;
        }
    }

    const tpEl = document.getElementById('metricThroughput');
    tpEl.innerHTML = formatNumber(throughput, 1) + '<span class="unit">/s</span>';

    // Peak throughput from C++ tracking
    const peakTp = data.peak_throughput || 0;
    const ptEl = document.getElementById('metricPeakThroughput');
    ptEl.innerHTML = formatNumber(peakTp, 1) + '<span class="unit">/s</span>';

    if (data.connection_stats && data.connection_stats.count > 0) {
        document.getElementById('metricConnTime').innerHTML = formatNumber(data.connection_stats.avg_ms, 0) + '<span class="unit">ms</span>';
    }

    // Update config bar values (once)
    if (data.config && document.getElementById('cfgServer').textContent === '--') {
        const c = data.config;
        const isWorkload = c.workload_mode === true;
        document.getElementById('cfgServer').textContent = c.server || 'localhost';
        document.getElementById('cfgDatabase').textContent = c.database || '--';
        document.getElementById('cfgAuth').textContent = c.authentication || '--';
        document.getElementById('cfgThreads').innerHTML = isWorkload ? '&lt;various&gt;' : (c.threads || '--');
        document.getElementById('cfgIterations').innerHTML = isWorkload ? '&lt;various&gt;' : (c.iterations || '--');
    }

    const queries = data.query_stats ? data.query_stats.queries : [];

    // Update queries count in config bar
    const qSpan = document.getElementById('cfgQueries');
    if (qSpan) qSpan.textContent = queries.length;

    // Update progress bar
    if (data.config && queries.length > 0) {
        // Use total_batches from config (works for both -workload and -i/-Q modes)
        const expected = data.config.total_batches || ((data.config.threads || 1) * (data.config.iterations_per_thread || 1) * queries.length);
        if (expected > 0) {
            const pct = Math.min(100, (totalExecs / expected) * 100);
            document.getElementById('progressRow').style.display = 'flex';
            document.getElementById('progressFill').style.width = pct.toFixed(1) + '%';
            document.getElementById('progressText').textContent = pct.toFixed(0) + '% (' + totalExecs.toLocaleString() + ' / ' + expected.toLocaleString() + ')';
            if (data.status === 'complete') {
                document.getElementById('progressFill').style.background = '#1a7f37';
            }
        }
    }

    // Compute workload start time from first snapshot
    if (!workloadStartTime && data.timestamp && data.elapsed_seconds > 0) {
        const snapshotDate = new Date(data.timestamp);
        workloadStartTime = new Date(snapshotDate.getTime() - data.elapsed_seconds * 1000);
    }

    // Update timestamp - show start time while running
    const startStr = workloadStartTime ? 'Start Run: ' + workloadStartTime.toLocaleString() : '';
    document.getElementById('lastUpdate').textContent = startStr;

    if (queries.length === 0) return;

    // Build labels
    const labels = queries.map((q, i) => 'Q' + (i+1));

    // Update charts
    // Elapsed Time: stacked (Server Elapsed + Client Overhead)
    charts.elapsed.data.labels = labels;
    charts.elapsed.data.datasets[0].data = queries.map(q => q.server_elapsed_ms.avg);
    charts.elapsed.data.datasets[1].data = queries.map(q => Math.max(0, q.total_elapsed_ms.avg - q.server_elapsed_ms.avg));
    charts.elapsed.update('none');

    updateChartData(charts.serverCpu, labels,
        queries.map(q => q.server_cpu_ms.avg),
        queries.map(q => q.server_cpu_ms.min),
        queries.map(q => q.server_cpu_ms.max));

    updateChartData(charts.logicalReads, labels,
        queries.map(q => q.logical_reads.avg),
        queries.map(q => q.logical_reads.min),
        queries.map(q => q.logical_reads.max));

    // Update Physical I/O stacked chart
    charts.physicalIO.data.labels = labels;
    charts.physicalIO.data.datasets[0].data = queries.map(q => q.physical_reads ? q.physical_reads.avg : 0);
    charts.physicalIO.data.datasets[1].data = queries.map(q => q.read_ahead_reads ? q.read_ahead_reads.avg : 0);
    charts.physicalIO.update('none');

    // Update throughput chart (exec/s per query = 1000 / avg elapsed ms)
    charts.throughput.data.labels = labels;
    charts.throughput.data.datasets[0].data = queries.map(q => q.total_elapsed_ms && q.total_elapsed_ms.avg > 0 ? (1000 / q.total_elapsed_ms.avg) : 0);
    charts.throughput.data.datasets[1].data = queries.map(q => q.total_elapsed_ms && q.total_elapsed_ms.max > 0 ? (1000 / q.total_elapsed_ms.max) : 0);
    charts.throughput.data.datasets[2].data = queries.map(q => q.total_elapsed_ms && q.total_elapsed_ms.min > 0 ? (1000 / q.total_elapsed_ms.min) : 0);
    charts.throughput.update('none');

    // Update doughnut chart (filter out queries with 0 executions)
    const execFiltered = [];
    for (let i = 0; i < queries.length; i++) {
        if (queries[i].executions > 0) execFiltered.push({ label: labels[i], data: queries[i].executions, origIndex: i });
    }
    charts.executions.data.labels = execFiltered.map(e => e.label);
    charts.executions.data.datasets[0].data = execFiltered.map(e => e.data);
    charts.executions.data.datasets[0].backgroundColor = doughnutColors.slice(0, execFiltered.length);
    charts.executions._execFilterMap = execFiltered;
    charts.executions.update('none');

    // Update aggregate totals (values only, structure pre-rendered in HTML)
    const t = data.query_stats.totals;
    const totalsEl = document.getElementById('aggregateTotals');
    totalsEl.querySelector('[data-metric="totalElapsed"]').textContent = formatNumber(t.total_elapsed_ms, 1);
    totalsEl.querySelector('[data-metric="serverElapsed"]').textContent = formatNumber(t.server_elapsed_ms, 1);
    totalsEl.querySelector('[data-metric="serverCpu"]').textContent = formatNumber(t.server_cpu_ms, 1);
    totalsEl.querySelector('[data-metric="logicalReads"]').textContent = t.logical_reads.toLocaleString();
    totalsEl.querySelector('[data-metric="physicalReads"]').textContent = (t.physical_reads || 0).toLocaleString();
    totalsEl.querySelector('[data-metric="readAheadReads"]').textContent = (t.read_ahead_reads || 0).toLocaleString();
    totalsEl.querySelector('[data-metric="executions"]').textContent = t.executions.toLocaleString();

    // Update detail table (rebuild structure only when query count changes, update values in-place otherwise)
    const container = document.getElementById('detailTableContainer');
    const existingRows = container.querySelectorAll('tr[id^="query-"]');
    if (existingRows.length !== queries.length) {
        // Rebuild table structure
        let html = '<table class="detail-table"><tr><th>#</th><th>Query</th><th style="text-align:right">Exec</th><th style="text-align:right">Fail</th><th style="text-align:right">Avg Total ms</th><th style="text-align:right">Avg Server ms</th><th style="text-align:right">Avg CPU ms</th><th style="text-align:right">Avg Logical Reads</th><th style="text-align:right">Avg Physical Reads</th><th style="text-align:right">Avg Read-Ahead</th><th style="text-align:right">Avg Rows</th></tr>';
        for (let i = 0; i < queries.length; i++) {
            const q = queries[i];
            const preview = q.query.replace(/\\n/g, ' ').replace(/\\s+/g, ' ');
            const escaped = preview.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
            const failCount = q.failures || 0;
            const failClass = failCount > 0 ? 'num color-red' : 'num';
            html += '<tr id="query-' + (i+1) + '">' +
                '<td class="query-num">Q' + (i+1) + '</td>' +
                '<td class="query-text" title="' + escaped + '">' + escaped + '</td>' +
                '<td class="num" data-col="exec">' + q.executions + '</td>' +
                '<td class="' + failClass + '" data-col="fail">' + failCount + '</td>' +
                '<td class="num" data-col="total">' + formatNumber(q.total_elapsed_ms.avg, 3) + '</td>' +
                '<td class="num" data-col="server">' + formatNumber(q.server_elapsed_ms.avg, 3) + '</td>' +
                '<td class="num" data-col="cpu">' + formatNumber(q.server_cpu_ms.avg, 3) + '</td>' +
                '<td class="num" data-col="lreads">' + formatNumber(q.logical_reads.avg, 1) + '</td>' +
                '<td class="num" data-col="preads">' + formatNumber(q.physical_reads ? q.physical_reads.avg : 0, 1) + '</td>' +
                '<td class="num" data-col="rareads">' + formatNumber(q.read_ahead_reads ? q.read_ahead_reads.avg : 0, 1) + '</td>' +
                '<td class="num" data-col="rows">' + formatNumber(q.row_count ? q.row_count.avg : 0, 1) + '</td>' +
                '</tr>';
        }
        html += '</table>';
        container.innerHTML = html;
    } else {
        // Update values in-place (no DOM rebuild)
        for (let i = 0; i < queries.length; i++) {
            const q = queries[i];
            const row = existingRows[i];
            row.querySelector('[data-col="exec"]').textContent = q.executions;
            const failCell = row.querySelector('[data-col="fail"]');
            const failCount = q.failures || 0;
            failCell.textContent = failCount;
            failCell.className = failCount > 0 ? 'num color-red' : 'num';
            row.querySelector('[data-col="total"]').textContent = formatNumber(q.total_elapsed_ms.avg, 3);
            row.querySelector('[data-col="server"]').textContent = formatNumber(q.server_elapsed_ms.avg, 3);
            row.querySelector('[data-col="cpu"]').textContent = formatNumber(q.server_cpu_ms.avg, 3);
            row.querySelector('[data-col="lreads"]').textContent = formatNumber(q.logical_reads.avg, 1);
            row.querySelector('[data-col="preads"]').textContent = formatNumber(q.physical_reads ? q.physical_reads.avg : 0, 1);
            row.querySelector('[data-col="rareads"]').textContent = formatNumber(q.read_ahead_reads ? q.read_ahead_reads.avg : 0, 1);
            row.querySelector('[data-col="rows"]').textContent = formatNumber(q.row_count ? q.row_count.avg : 0, 1);
        }
    }
}

function finalizeWorkload() {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    const badge = document.getElementById('statusBadge');
    const totalErrors = lastData ? (lastData.total_errors || 0) : 0;
    const totalWarnings = lastData ? (lastData.total_warnings || 0) : 0;
    if (totalErrors > 0) {
        badge.textContent = 'ERRORS: ' + totalErrors;
        badge.className = 'status-badge status-error';
    } else if (totalWarnings > 0) {
        badge.textContent = 'WARNINGS: ' + totalWarnings;
        badge.className = 'status-badge status-warning';
    } else {
        badge.textContent = 'COMPLETE';
        badge.className = 'status-badge status-complete';
    }
    // Set progress to 100%
    const fill = document.getElementById('progressFill');
    const text = document.getElementById('progressText');
    if (fill) { fill.style.width = '100%'; fill.style.background = '#1a7f37'; }
    if (text && lastData && lastData.query_stats && lastData.query_stats.totals) {
        const total = lastData.query_stats.totals.executions;
        text.textContent = '100% (' + total.toLocaleString() + ' / ' + total.toLocaleString() + ')';
    }
    // Show start — end timestamps
    const startStr = workloadStartTime ? 'Start Run: ' + workloadStartTime.toLocaleString() : '';
    const endStr = lastData && lastData.timestamp ? new Date(lastData.timestamp).toLocaleString() : new Date().toLocaleString();
    document.getElementById('lastUpdate').textContent = startStr + ' \u2014 End Run: ' + endStr;
    document.getElementById('saveBtn').style.display = 'inline-block';
}

async function pollData() {
    try {
        const resp = await fetch('/stats.json?t=' + Date.now());
        if (resp.ok) {
            fetchFailCount = 0;
            const data = await resp.json();
            updateDashboard(data);

            // Stop polling when complete
            if (data.status === 'complete') {
                finalizeWorkload();
            }
        } else {
            fetchFailCount++;
        }
    } catch (e) {
        fetchFailCount++;
    }
    // If server went away (consecutive failures), treat as workload complete
    if (fetchFailCount >= MAX_FETCH_FAILS && lastData && pollTimer) {
        finalizeWorkload();
    }
}

// Doughnut colors (matching static report)
const doughnutColors = [
    'rgba(56, 189, 248, 0.75)', 'rgba(52, 211, 153, 0.75)', 'rgba(251, 191, 36, 0.75)',
    'rgba(192, 132, 252, 0.75)', 'rgba(248, 113, 113, 0.75)', 'rgba(96, 165, 250, 0.75)',
    'rgba(74, 222, 128, 0.75)', 'rgba(253, 224, 71, 0.75)', 'rgba(167, 139, 250, 0.75)',
    'rgba(251, 146, 60, 0.75)', 'rgba(244, 114, 182, 0.75)', 'rgba(45, 212, 191, 0.75)'
];

// Initialize charts
// Elapsed Time: stacked chart (Server Elapsed + Client Overhead)
(function() {
    const serverColor = CHART_COLORS.serverElapsed;
    const networkColor = CHART_COLORS.totalElapsed;
    const ctx = document.getElementById('chartElapsed').getContext('2d');
    charts.elapsed = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: [],
            datasets: [
                { label: 'Server Elapsed', data: [], backgroundColor: serverColor, borderRadius: 3, borderSkipped: false },
                { label: 'Client Overhead', data: [], backgroundColor: networkColor, borderRadius: 3, borderSkipped: false }
            ]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            maintainAspectRatio: true,
            animation: { duration: 400 },
            onHover: function(evt, elements) {
                this.canvas.style.cursor = elements.length > 0 ? 'pointer' : 'default';
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
                        title: function(items) {
                            if (lastData && lastData.query_stats && lastData.query_stats.queries) {
                                const idx = items[0].dataIndex;
                                const q = lastData.query_stats.queries[idx];
                                if (q) {
                                    const text = q.query.replace(/\\n/g, ' ').replace(/\\s+/g, ' ');
                                    const preview = text.length > 80 ? text.substring(0, 77) + '...' : text;
                                    let title = 'Q' + (idx+1) + ': ' + preview;
                                    if (q.failures > 0) title += ' (' + q.failures + ' failed)';
                                    return title;
                                }
                            }
                            return items[0].label;
                        },
                        label: (item) => '  ' + item.dataset.label + ': ' + item.raw.toFixed(3) + ' ms'
                    }
                }
            },
            scales: {
                x: { stacked: true, grid: { color: '#e1e4e8' }, ticks: { color: '#656d76', font: { size: 11 } } },
                y: { stacked: true, grid: { display: false }, ticks: { color: '#bc4c00', font: { size: 12, weight: 'bold' } } }
            },
            onClick: function(evt) {
                const elements = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, false);
                if (elements.length > 0) scrollToQuery(elements[0].index + 1);
            }
        }
    });
    addYAxisClickListener(charts.elapsed, 1);
})();

charts.serverCpu = createChart('chartServerCpu', 'Server CPU (ms)', CHART_COLORS.serverCpu, 'ms');
charts.logicalReads = createChart('chartLogicalReads', 'Logical Reads', CHART_COLORS.logicalReads, 'pages');

// Physical I/O: stacked chart with Physical Reads + Read-ahead Reads
(function() {
    const physColor = CHART_COLORS.physicalReads;
    const raColor = CHART_COLORS.readAheadReads;
    const ctx = document.getElementById('chartPhysicalIO').getContext('2d');
    charts.physicalIO = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: [],
            datasets: [
                { label: 'Physical Reads', data: [], backgroundColor: physColor, borderRadius: 3, borderSkipped: false },
                { label: 'Read-ahead Reads', data: [], backgroundColor: raColor, borderRadius: 3, borderSkipped: false }
            ]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            maintainAspectRatio: true,
            animation: { duration: 400 },
            onHover: function(evt, elements) {
                this.canvas.style.cursor = elements.length > 0 ? 'pointer' : 'default';
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
                        title: function(items) {
                            if (lastData && lastData.query_stats && lastData.query_stats.queries) {
                                const idx = items[0].dataIndex;
                                const q = lastData.query_stats.queries[idx];
                                if (q) {
                                    const text = q.query.replace(/\\n/g, ' ').replace(/\\s+/g, ' ');
                                    const preview = text.length > 80 ? text.substring(0, 77) + '...' : text;
                                    let title = 'Q' + (idx+1) + ': ' + preview;
                                    if (q.failures > 0) title += ' (' + q.failures + ' failed)';
                                    return title;
                                }
                            }
                            return items[0].label;
                        },
                        label: (item) => '  ' + item.dataset.label + ': ' + item.raw.toFixed(1) + ' pages'
                    }
                }
            },
            scales: {
                x: { stacked: true, grid: { color: '#e1e4e8' }, ticks: { color: '#656d76', font: { size: 11 } } },
                y: { stacked: true, grid: { display: false }, ticks: { color: '#bc4c00', font: { size: 12, weight: 'bold' } } }
            },
            onClick: function(evt) {
                const elements = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, false);
                if (elements.length > 0) scrollToQuery(elements[0].index + 1);
            }
        }
    });
    addYAxisClickListener(charts.physicalIO, 1);
})();

// Throughput per Query bar chart (exec/s)
charts.throughput = createChart('chartThroughput', 'Throughput (exec/s)', 'rgba(96, 165, 250, 0.85)', 'exec/s');

// Execution Distribution doughnut
(function() {
    const ctx = document.getElementById('chartExecutions').getContext('2d');
    charts.executions = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: [],
            datasets: [{
                data: [],
                backgroundColor: doughnutColors,
                borderColor: '#ffffff',
                borderWidth: 2
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            animation: { animateRotate: true, duration: 400 },
            onClick: (evt, elements) => {
                if (elements.length > 0) {
                    const chart = charts.executions;
                    const filterMap = chart._execFilterMap;
                    if (filterMap && filterMap[elements[0].index]) {
                        scrollToQuery(filterMap[elements[0].index].origIndex + 1);
                    }
                }
            },
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
                        title: function(items) {
                            const chart = charts.executions;
                            const filterMap = chart._execFilterMap;
                            if (filterMap) {
                                const idx = items[0].dataIndex;
                                const entry = filterMap[idx];
                                if (entry && lastData && lastData.query_stats && lastData.query_stats.queries) {
                                    const q = lastData.query_stats.queries[entry.origIndex];
                                    if (q) {
                                        const text = q.query.replace(/\\n/g, ' ').replace(/\\s+/g, ' ');
                                        const preview = text.length > 80 ? text.substring(0, 77) + '...' : text;
                                        return 'Q' + (entry.origIndex+1) + ': ' + preview;
                                    }
                                }
                            }
                            return items[0].label;
                        },
                        label: function(item) {
                            const total = item.dataset.data.reduce((a, b) => a + b, 0);
                            return '  ' + item.raw + ' executions (' + ((item.raw / total) * 100).toFixed(1) + '%)';
                        }
                    }
                }
            }
        }
    });
})();

function saveReport() {
    if (!lastData) return;
    const d = lastData;
    const ts = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19);
    const chartImages = {};
    for (const [key, chart] of Object.entries(charts)) {
        chartImages[key] = chart.toBase64Image();
    }

    // Build metrics HTML
    const elapsed = d.elapsed_seconds ? d.elapsed_seconds.toFixed(1) : '0';
    const totalExecs = d.query_stats && d.query_stats.totals ? d.query_stats.totals.executions : 0;
    const execElapsed = d.execution_elapsed_seconds || 0;
    const throughput = execElapsed > 0 ? (totalExecs / execElapsed).toFixed(1) : '0';
    const peakThroughput = d.peak_throughput ? d.peak_throughput.toFixed(1) : '0';
    const connAvg = d.connection_stats ? d.connection_stats.avg_ms.toFixed(1) : '--';
    const queryCount = d.query_stats && d.query_stats.queries ? d.query_stats.queries.length : 0;

    // Build config for saved report
    const cfg = d.config || {};

    // Build error/warning data for saved report
    const savedTotalErrors = d.total_errors || 0;
    const savedTotalWarnings = d.total_warnings || 0;
    let savedAlertHtml = '';
    // Build queries array for Q# matching in saved report
    const savedQueries = (d.query_stats && d.query_stats.queries) ? d.query_stats.queries : [];
    function savedMatchQueryToNum(queryText) {
        if (!queryText) return { label: '', num: 0 };
        const clean = queryText.replace(/\r?\n/g, ' ').replace(/\s+/g, ' ').trim();
        for (let i = 0; i < savedQueries.length; i++) {
            const statsClean = (savedQueries[i].query || '').replace(/\r?\n/g, ' ').replace(/\s+/g, ' ').trim();
            if (statsClean === clean) return { label: 'Q' + (i + 1), num: i + 1 };
        }
        const fallback = clean.length > 60 ? escapeHtml(clean.substring(0, 60) + '...') : escapeHtml(clean);
        return { label: fallback, num: 0 };
    }
    if (savedTotalErrors > 0 && d.recent_errors && d.recent_errors.length > 0) {
        const items = d.recent_errors.map(e => {
            const ts = e.timestamp ? '<span class="msg-time">' + escapeHtml(e.timestamp) + '</span>' : '';
            const match = savedMatchQueryToNum(e.query);
            let qCell = '';
            if (match.num > 0) {
                qCell = '<a href="#query-' + match.num + '" style="color:#bc4c00;font-weight:600;text-decoration:none" onclick="var r=document.getElementById(\'query-' + match.num + '\');if(r){r.style.background=\'#fff3cd\';setTimeout(function(){r.style.background=\'\';},2000);}">' + match.label + '</a> ';
            } else if (match.label) {
                qCell = '<span style="color:#bc4c00;font-weight:600">' + match.label + '</span> ';
            }
            return '<li>' + ts + qCell + escapeHtml(e.message) + '</li>';
        }).join('');
        const suffix = savedTotalErrors > d.recent_errors.length ? ' (showing ' + d.recent_errors.length + ' of ' + savedTotalErrors + ')' : '';
        savedAlertHtml += '<div class="alert-box alert-error" id="saved-errors-section"><h4>Errors: ' + savedTotalErrors + suffix + '</h4><ul>' + items + '</ul></div>\n';
    }
    if (savedTotalWarnings > 0 && d.recent_warnings && d.recent_warnings.length > 0) {
        const items = d.recent_warnings.map(w => {
            const ts = w.timestamp ? '<span class="msg-time">' + escapeHtml(w.timestamp) + '</span>' : '';
            const match = savedMatchQueryToNum(w.query);
            let qCell = '';
            if (match.num > 0) {
                qCell = '<a href="#query-' + match.num + '" style="color:#bc4c00;font-weight:600;text-decoration:none" onclick="var r=document.getElementById(\'query-' + match.num + '\');if(r){r.style.background=\'#fff3cd\';setTimeout(function(){r.style.background=\'\';},2000);}">' + match.label + '</a> ';
            } else if (match.label) {
                qCell = '<span style="color:#bc4c00;font-weight:600">' + match.label + '</span> ';
            }
            return '<li>' + ts + qCell + escapeHtml(w.message) + '</li>';
        }).join('');
        const suffix = savedTotalWarnings > d.recent_warnings.length ? ' (showing ' + d.recent_warnings.length + ' of ' + savedTotalWarnings + ')' : '';
        savedAlertHtml += '<div class="alert-box alert-warning" id="saved-warnings-section"><h4>Warnings: ' + savedTotalWarnings + suffix + '</h4><ul>' + items + '</ul></div>\n';
    }

    const chartNames = {
        elapsed: 'Elapsed Time (ms)',
        serverCpu: 'Server CPU Time (ms)',
        logicalReads: 'Logical Reads (pages)',
        physicalIO: 'Physical I/O (pages)',
        throughput: 'Throughput per Query (exec/s)',
        executions: 'Execution Distribution'
    };

    // Build chart images in 2-column rows (matching static report layout)
    const chartOrder = ['elapsed', 'serverCpu', 'logicalReads', 'physicalIO', 'throughput', 'executions'];
    let chartsHtml = '';
    for (let i = 0; i < chartOrder.length; i += 2) {
        chartsHtml += '<div class="chart-row">';
        for (let j = i; j < Math.min(i + 2, chartOrder.length); j++) {
            const key = chartOrder[j];
            const img = chartImages[key];
            if (img) {
                chartsHtml += '<div class="chart-box"><h3>' + chartNames[key] + '</h3><img src="' + img + '" style="width:100%;max-height:260px;"></div>';
            }
        }
        chartsHtml += '</div>';
    }

    // Build aggregate totals (matching static report)
    let totalsHtml = '';
    if (d.query_stats && d.query_stats.totals) {
        const t = d.query_stats.totals;
        totalsHtml = '<div style="background:linear-gradient(135deg,#f0f4ff 0%,#e8f0fe 100%);border:2px solid #4a90d9;border-radius:6px;padding:16px;margin-bottom:10px;">' +
            '<h3 style="color:#1a56db;font-size:15px;margin-bottom:12px;">Aggregate Totals</h3>' +
            '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;">' +
            '<div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;"><div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Total Elapsed</div><div style="font-size:18px;font-weight:700;color:#1a56db;font-family:\'Cascadia Code\',\'Consolas\',monospace;">' + t.total_elapsed_ms.toFixed(1) + '<span style="font-size:11px;font-weight:400;color:#656d76;"> ms</span></div></div>' +
            '<div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;"><div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Server Elapsed</div><div style="font-size:18px;font-weight:700;color:#1a7f37;font-family:\'Cascadia Code\',\'Consolas\',monospace;">' + t.server_elapsed_ms.toFixed(1) + '<span style="font-size:11px;font-weight:400;color:#656d76;"> ms</span></div></div>' +
            '<div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;"><div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Server CPU</div><div style="font-size:18px;font-weight:700;color:#bc4c00;font-family:\'Cascadia Code\',\'Consolas\',monospace;">' + t.server_cpu_ms.toFixed(1) + '<span style="font-size:11px;font-weight:400;color:#656d76;"> ms</span></div></div>' +
            '<div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;"><div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Logical Reads</div><div style="font-size:18px;font-weight:700;color:#8250df;font-family:\'Cascadia Code\',\'Consolas\',monospace;">' + t.logical_reads.toLocaleString() + '</div></div>' +
            '<div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;"><div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Physical Reads</div><div style="font-size:18px;font-weight:700;color:#cf222e;font-family:\'Cascadia Code\',\'Consolas\',monospace;">' + (t.physical_reads || 0).toLocaleString() + '</div></div>' +
            '<div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;"><div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Read-ahead Reads</div><div style="font-size:18px;font-weight:700;color:#d97706;font-family:\'Cascadia Code\',\'Consolas\',monospace;">' + (t.read_ahead_reads || 0).toLocaleString() + '</div></div>' +
            '<div style="background:#fff;border-radius:6px;padding:10px 14px;border:1px solid #d0d7de;text-align:center;"><div style="font-size:10px;color:#656d76;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Executions</div><div style="font-size:18px;font-weight:700;color:#1f2328;font-family:\'Cascadia Code\',\'Consolas\',monospace;">' + t.executions.toLocaleString() + '</div></div>' +
            '</div></div>';
    }

    // Build detail table (matching static report)
    let tableHtml = '';
    if (d.query_stats && d.query_stats.queries) {
        tableHtml = '<table class="detail-table"><tr><th>#</th><th>Query</th><th style="text-align:right">Exec</th><th style="text-align:right">Fail</th><th style="text-align:right">Avg Total ms</th><th style="text-align:right">Avg Server ms</th><th style="text-align:right">Avg CPU ms</th><th style="text-align:right">Avg Logical Reads</th><th style="text-align:right">Avg Physical Reads</th><th style="text-align:right">Avg Read-Ahead</th><th style="text-align:right">Avg Rows</th></tr>';
        d.query_stats.queries.forEach((q, i) => {
            const preview = q.query.replace(/\n/g, ' ').replace(/\s+/g, ' ');
            const escaped = preview.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
            const failCount = q.failures || 0;
            const failClass = failCount > 0 ? 'num color-red' : 'num';
            tableHtml += '<tr id="query-' + (i+1) + '"><td class="query-num">Q' + (i+1) + '</td><td class="query-text" title="' + escaped + '">' + escaped + '</td>' +
                '<td class="num">' + q.executions + '</td>' +
                '<td class="' + failClass + '">' + failCount + '</td>' +
                '<td class="num">' + q.total_elapsed_ms.avg.toFixed(3) + '</td>' +
                '<td class="num">' + q.server_elapsed_ms.avg.toFixed(3) + '</td>' +
                '<td class="num">' + q.server_cpu_ms.avg.toFixed(3) + '</td>' +
                '<td class="num">' + q.logical_reads.avg.toFixed(1) + '</td>' +
                '<td class="num">' + (q.physical_reads ? q.physical_reads.avg.toFixed(1) : '0.0') + '</td>' +
                '<td class="num">' + (q.read_ahead_reads ? q.read_ahead_reads.avg.toFixed(1) : '0.0') + '</td>' +
                '<td class="num">' + (q.row_count ? q.row_count.avg.toFixed(1) : '0.0') + '</td></tr>';
        });
        tableHtml += '</table>';
    }

    const savedHtml = '<!DOCTYPE html>\n' +
        '<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>sqlsim Query Stats Report - ' + ts + '</title>\n' +
        '<style>\n' +
        '* { margin: 0; padding: 0; box-sizing: border-box; }\n' +
        'body { font-family: "Segoe UI", -apple-system, BlinkMacSystemFont, sans-serif; background: #f6f8fa; color: #1f2328; padding: 16px; line-height: 1.4; }\n' +
        '.container { max-width: 1400px; margin: 0 auto; }\n' +
        '.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; padding-bottom: 8px; border-bottom: 1px solid #d0d7de; }\n' +
        '.header h1 { font-size: 16px; font-weight: 600; color: #0969da; }\n' +
        '.header h1 span { color: #656d76; font-weight: 400; font-size: 13px; }\n' +
        '.badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }\n' +
        '.badge-success { background: #1a7f37; color: #fff; }\n' +
        '.info-grid { font-size: 11px; color: #656d76; margin-bottom: 8px; padding: 4px 0; }\n' +
        '.info-grid span { margin-right: 14px; }\n' +
        '.info-grid .cfg-label { font-weight: 600; color: #8b949e; text-transform: uppercase; font-size: 10px; letter-spacing: 0.3px; margin-right: 3px; }\n' +
        '.section { background: #ffffff; border: 1px solid #d0d7de; border-radius: 6px; padding: 14px; margin-bottom: 10px; }\n' +
        '.section h3 { font-size: 14px; font-weight: 600; margin-bottom: 10px; color: #1f2328; }\n' +
        '.chart-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 10px; }\n' +
        '@media (max-width: 900px) { .chart-row { grid-template-columns: 1fr; } }\n' +
        '.chart-box { background: #ffffff; border: 1px solid #d0d7de; border-radius: 6px; padding: 12px; }\n' +
        '.chart-box h3 { font-size: 13px; font-weight: 600; margin-bottom: 6px; color: #1f2328; }\n' +
        '.detail-table { width: 100%; border-collapse: collapse; margin-top: 6px; }\n' +
        '.detail-table th, .detail-table td { padding: 6px 10px; text-align: left; border-bottom: 1px solid #d0d7de; font-size: 13px; }\n' +
        '.detail-table th { color: #656d76; font-weight: 600; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; }\n' +
        '.detail-table td.num { text-align: right; font-family: "Cascadia Code", "Consolas", monospace; }\n' +
        '.detail-table td.query-num { color: #bc4c00; font-weight: 600; width: 40px; }\n' +
        '.detail-table td.query-text { max-width: 400px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: #656d76; font-size: 12px; font-family: "Cascadia Code", "Consolas", monospace; }\n' +
        '.detail-table tr:hover { background: #f3f4f6; }\n' +
        '.footer { margin-top: 16px; padding-top: 10px; border-top: 1px solid #d0d7de; color: #656d76; font-size: 12px; text-align: center; }\n' +
        '.footer a { color: #0969da; text-decoration: none; }\n' +
        '.badge-error { background: #cf222e; color: #fff; }\n' +
        '.badge-warning { background: #d4a017; color: #fff; }\n' +
        '.alert-box { border-radius: 6px; padding: 10px 14px; margin-bottom: 10px; font-size: 12px; }\n' +
        '.alert-box h4 { font-size: 13px; font-weight: 600; margin-bottom: 6px; }\n' +
        '.alert-box ul { margin: 0; padding-left: 18px; }\n' +
        '.alert-box li { margin-bottom: 3px; }\n' +
        '.alert-error { background: #fef2f2; border: 1px solid #fca5a5; color: #991b1b; }\n' +
        '.alert-warning { background: #fefce8; border: 1px solid #fde68a; color: #854d0e; }\n' +
        '.msg-time { font-size: 10px; color: #656d76; margin-right: 6px; font-family: "Cascadia Code","Consolas",monospace; }\n' +
        '.metrics-bar { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 10px; }\n' +
        '.metric-card { background: #ffffff; border: 1px solid #d0d7de; border-radius: 6px; padding: 6px 10px; flex: 1; min-width: 120px; }\n' +
        '.metric-card .label { font-size: 10px; color: #656d76; text-transform: uppercase; letter-spacing: 0.5px; }\n' +
        '.metric-card .value { font-size: 18px; font-weight: 700; font-variant-numeric: tabular-nums; }\n' +
        '.metric-card .unit { font-size: 11px; color: #656d76; font-weight: 400; }\n' +
        '.color-blue { color: #0969da; }\n' +
        '.color-purple { color: #8250df; }\n' +
        '.color-green { color: #1a7f37; }\n' +
        '.color-steel { color: #57606a; }\n' +
        '.color-teal { color: #0d9488; }\n' +
        '.color-red { color: #cf222e; }\n' +
        '.color-amber { color: #d4a017; }\n' +
        '</style></head><body>\n' +
        '<div class="container">\n' +
        '<div class="header"><div><h1>sqlsim Query Stats Report <span>' + (workloadStartTime ? 'Start Run: ' + workloadStartTime.toLocaleString() : '') + ' \u2014 End Run: ' + (d.timestamp ? new Date(d.timestamp).toLocaleString() : new Date().toLocaleString()) + '</span></h1></div><div>' + (savedTotalErrors > 0 || savedTotalWarnings > 0 ? '<a href="#saved-errors-section" style="text-decoration:none">' : '') + '<span class="badge ' + (savedTotalErrors > 0 ? 'badge-error' : savedTotalWarnings > 0 ? 'badge-warning' : 'badge-success') + '" style="cursor:pointer">' + (savedTotalErrors > 0 && savedTotalWarnings > 0 ? 'ERRORS: ' + savedTotalErrors + ' | WARNINGS: ' + savedTotalWarnings : savedTotalErrors > 0 ? 'ERRORS: ' + savedTotalErrors : savedTotalWarnings > 0 ? 'WARNINGS: ' + savedTotalWarnings : 'SUCCESS') + '</span>' + (savedTotalErrors > 0 || savedTotalWarnings > 0 ? '</a>' : '') + '</div></div>\n' +
        '<div class="metrics-bar">' +
            '<div class="metric-card"><div class="label">Runtime</div><div class="value color-blue">' + elapsed + '<span class="unit">s</span></div></div>' +
            '<div class="metric-card"><div class="label">Executions</div><div class="value color-purple">' + totalExecs.toLocaleString() + '</div></div>' +
            '<div class="metric-card"><div class="label">Throughput</div><div class="value color-green">' + throughput + '<span class="unit">/s</span></div></div>' +
            '<div class="metric-card"><div class="label">Peak Throughput</div><div class="value color-teal">' + peakThroughput + '<span class="unit">/s</span></div></div>' +
            '<div class="metric-card"><div class="label">Avg Connect</div><div class="value color-steel">' + connAvg + '<span class="unit">ms</span></div></div>' +
            (savedTotalErrors > 0 ? '<a href="#saved-errors-section" style="text-decoration:none"><div class="metric-card" style="cursor:pointer"><div class="label">Errors</div><div class="value color-red">' + savedTotalErrors + '</div></div></a>' : '') +
            (savedTotalWarnings > 0 ? '<a href="#saved-warnings-section" style="text-decoration:none"><div class="metric-card" style="cursor:pointer"><div class="label">Warnings</div><div class="value color-amber">' + savedTotalWarnings + '</div></div></a>' : '') +
        '</div>\n' +
        '<div class="info-grid">' +
            '<span><span class="cfg-label">Server</span>' + (cfg.server || 'localhost') + '</span>' +
            '<span><span class="cfg-label">Database</span>' + (cfg.database || '--') + '</span>' +
            '<span><span class="cfg-label">Auth</span>' + (cfg.authentication || '--') + '</span>' +
            '<span><span class="cfg-label">Threads</span>' + (cfg.workload_mode ? '&lt;various&gt;' : (cfg.threads || '--')) + '</span>' +
            '<span><span class="cfg-label">Iterations</span>' + (cfg.workload_mode ? '&lt;various&gt;' : (cfg.iterations || '--')) + '</span>' +
            '<span><span class="cfg-label">Queries</span>' + queryCount + '</span>' +
            '<span><span class="cfg-label">Executions</span>' + totalExecs.toLocaleString() + '</span>' +
            '<span><span class="cfg-label">Runtime</span>' + elapsed + 's</span>' +
        '</div>\n' +
        chartsHtml + '\n' +
        totalsHtml + '\n' +
        '<div class="section"><h3>Per-Query Detail</h3>' + tableHtml + '</div>\n' +
        savedAlertHtml +
        '<div class="footer">Generated by sqlsim querystats-chart.ps1 &bull; ' + new Date().toLocaleString() + '</div>\n' +
        '</div></body></html>';

    const blob = new Blob([savedHtml], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'querystats-report-' + ts + '.html';
    a.click();
    URL.revokeObjectURL(url);
}

// Start polling
pollData();
pollTimer = setInterval(pollData, POLL_INTERVAL);
</script>
</body>
</html>
"@

# --- Start HTTP Server ---

Write-Host "Starting HTTP server on port $Port..." -ForegroundColor Gray

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
} catch {
    Write-Host "Error: Could not start HTTP server on port $Port." -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkRed
    Write-Host "  Try a different port with -Port <number>" -ForegroundColor Yellow
    
    # Kill sqlsim
    if ($sqlsimProcess -and -not $sqlsimProcess.HasExited) {
        $sqlsimProcess.Kill()
    }
    exit 1
}

Write-Host "Dashboard ready!" -ForegroundColor Green
Write-Host ""
Write-Host "  Open: http://localhost:$Port/" -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

# Open browser
if (-not $NoOpen) {
    Start-Process "http://localhost:$Port/"
}

# --- Serve requests ---

$sqlsimExitTime = $null
$contextTask = $null
$lastGoodJson = '{"status":"waiting","elapsed_seconds":0,"query_stats":{"queries":[],"totals":{"executions":0}}}'

try {
    while ($listener.IsListening) {
        # Track when sqlsim exits
        if (-not $sqlsimExitTime -and $sqlsimProcess.HasExited) {
            $sqlsimExitTime = [DateTime]::UtcNow
        }
        
        # Exit condition: sqlsim done + grace period expired (serve final data for at least Interval+5 seconds)
        if ($sqlsimExitTime) {
            $graceSec = ([DateTime]::UtcNow - $sqlsimExitTime).TotalSeconds
            if ($graceSec -gt ($Interval + 5)) {
                Write-Host ""
                Write-Host "sqlsim workload complete. Dashboard served." -ForegroundColor Green
                break
            }
        }
        
        # Reuse the same async task until it completes — creating a new one each iteration
        # causes orphaned tasks that swallow incoming requests
        if ($null -eq $contextTask) {
            $contextTask = $listener.GetContextAsync()
        }
        
        # Wait for request with short timeout so we can check exit condition
        if (-not $contextTask.AsyncWaitHandle.WaitOne(500)) {
            continue
        }
        
        $context = $contextTask.Result
        $contextTask = $null  # Reset so next iteration creates a fresh task
        $request = $context.Request
        $response = $context.Response
        
        $path = $request.Url.AbsolutePath
        
        if ($path -eq "/" -or $path -eq "/index.html") {
            # Serve dashboard HTML
            $response.ContentType = "text/html; charset=utf-8"
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($dashboardHtml)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            
        } elseif ($path -eq "/stats.json") {
            # Serve querystats snapshot (with caching to handle file contention)
            $response.ContentType = "application/json"
            $response.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            
            try {
                if (Test-Path $snapshotFile) {
                    $jsonContent = [System.IO.File]::ReadAllText($snapshotFile)
                    if ($jsonContent -and $jsonContent.Length -gt 10) {
                        $lastGoodJson = $jsonContent
                    }
                }
            } catch {
                # File locked by C++ writer — serve last good cached data
            }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($lastGoodJson)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            
        } else {
            # 404
            $response.StatusCode = 404
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("Not found")
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        
        $response.Close()
    }
} catch {
    if ($_.Exception.Message -notlike "*thread was being aborted*" -and 
        $_.Exception.Message -notlike "*Cannot access a disposed object*") {
        Write-Host "Server error: $($_.Exception.Message)" -ForegroundColor Red
    }
} finally {
    # Cleanup
    Write-Host ""
    Write-Host "Cleaning up..." -ForegroundColor Gray
    
    try { $listener.Stop() } catch { }
    try { $listener.Close() } catch { }
    
    if ($sqlsimProcess -and -not $sqlsimProcess.HasExited) {
        Write-Host "Stopping sqlsim..." -ForegroundColor Gray
        try { $sqlsimProcess.Kill() } catch { }
    }
    
    # Clean up temp files
    Remove-Item $snapshotFile -ErrorAction SilentlyContinue
    Remove-Item "$snapshotFile.tmp" -ErrorAction SilentlyContinue
    Remove-Item $sqlsimLogFile -ErrorAction SilentlyContinue
    Remove-Item "$sqlsimLogFile.err" -ErrorAction SilentlyContinue
    
    Write-Host "Done." -ForegroundColor Green
}
