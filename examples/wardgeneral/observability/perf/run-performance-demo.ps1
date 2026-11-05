<#
.SYNOPSIS
    Run the complete Observability Hyperscale performance investigation.

.DESCRIPTION
    Captures RBPEX and page-server counters, removes clean pages from the buffer
    pool with DBCC DROPCLEANBUFFERS, runs exactly three concurrent read-only
    scans, and reports which lower cache tiers served the workload. It also runs
    the database drill-down, retrieves Azure Monitor metrics for the same UTC
    interval, and writes one machine-readable summary plus the raw evidence.

    The workload can consume substantial CPU. Clearing the buffer pool can
    temporarily affect other users, so never run this against production. The
    script changes no data and does not clear RBPEX, tune, scale, fail over, or
    create an index.

.PARAMETER Server
    Azure SQL logical-server FQDN. Defaults to WardGeneral__Server, including a
    value loaded from first-app/wardgeneral.env when that file exists.

.PARAMETER Database
    Database name. Defaults to WardGeneral__Database, then wardgeneral.

.PARAMETER SqlCmd
    Explicit path to the new Go-based sqlcmd.

.PARAMETER OutputDirectory
    Evidence directory. Defaults to a timestamped folder under the current
    user's temporary directory.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd,
    [string] $OutputDirectory
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

Then open a new PowerShell session, or set SQLCMD to its full path.
'@
}

$az = (Get-Command az -ErrorAction SilentlyContinue).Source
if (-not $az) {
    throw 'Azure CLI was not found. Install it and run az login before starting this demo.'
}
& $az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not signed in. Run az login, then start the demo again.'
}

if (-not $OutputDirectory) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) "wardgeneral-observability-performance-$stamp"
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

$launcher = Join-Path $here 'run-concurrent-scans.ps1'
$drilldown = Join-Path $here 'performance-drilldown.sql'
$drilldownOutput = Join-Path $OutputDirectory 'performance-drilldown.txt'
$metricsOutput = Join-Path $OutputDirectory 'azure-monitor-metrics.json'
$summaryOutput = Join-Path $OutputDirectory 'run-summary.json'

function Get-PageServerFileStats {
    $query = @'
SET NOCOUNT ON;
SELECT CONCAT(
    N'CH07_VFS|',
    COALESCE(SUM(num_of_reads), 0), N'|',
    COALESCE(SUM(num_of_bytes_read), 0), N'|',
    COALESCE(SUM(io_stall_read_ms), 0)
)
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL)
WHERE file_id <> 2;
'@
    $output = & $sqlcmdPath -S $Server -d $Database -G -C -b -W -h -1 -Q $query
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the page-server virtual-file counters.'
    }
    $match = [regex]::Match(($output -join [Environment]::NewLine),
        'CH07_VFS\|(?<reads>\d+)\|(?<bytes>\d+)\|(?<stall>\d+)')
    if (-not $match.Success) {
        throw 'The page-server virtual-file counters returned an unexpected result.'
    }
    [pscustomobject]@{
        Reads = [int64]$match.Groups['reads'].Value
        BytesRead = [int64]$match.Groups['bytes'].Value
        ReadStallMs = [int64]$match.Groups['stall'].Value
    }
}

function Get-RbpexFileStats {
    $query = @'
SET NOCOUNT ON;
SELECT CONCAT(
    N'CH07_RBPEX|',
    COALESCE(SUM(num_of_reads), 0), N'|',
    COALESCE(SUM(num_of_bytes_read), 0), N'|',
    COALESCE(SUM(io_stall_read_ms), 0)
)
FROM sys.dm_io_virtual_file_stats(0, NULL);
'@
    $output = & $sqlcmdPath -S $Server -d $Database -G -C -b -W -h -1 -Q $query
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the RBPEX virtual-file counters.'
    }
    $match = [regex]::Match(($output -join [Environment]::NewLine),
        'CH07_RBPEX\|(?<reads>\d+)\|(?<bytes>\d+)\|(?<stall>\d+)')
    if (-not $match.Success) {
        throw 'The RBPEX virtual-file counters returned an unexpected result.'
    }
    [pscustomobject]@{
        Reads = [int64]$match.Groups['reads'].Value
        BytesRead = [int64]$match.Groups['bytes'].Value
        ReadStallMs = [int64]$match.Groups['stall'].Value
    }
}

function Clear-CleanBufferPoolPages {
    $output = & $sqlcmdPath -S $Server -d $Database -G -C -b -W -h -1 `
        -Q 'DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;'
    if ($LASTEXITCODE -ne 0) {
        throw 'DBCC DROPCLEANBUFFERS failed. The connecting principal must have permission to run it.'
    }
}

Write-Host 'Observability — Hyperscale performance investigation' -ForegroundColor Cyan
Write-Host "Server   : $Server" -ForegroundColor Gray
Write-Host "Database : $Database" -ForegroundColor Gray
Write-Host "Evidence : $OutputDirectory" -ForegroundColor Gray
Write-Host ''

$pageServerBefore = Get-PageServerFileStats
$rbpexBefore = Get-RbpexFileStats
Write-Host 'Removing clean pages from the buffer pool; RBPEX is left intact...' -ForegroundColor Yellow
Clear-CleanBufferPoolPages
$startedAtUtc = [DateTime]::UtcNow
& $launcher -Server $Server -Database $Database -SqlCmd $sqlcmdPath -OutputDirectory $OutputDirectory
$finishedAtUtc = [DateTime]::UtcNow
$pageServerAfter = Get-PageServerFileStats
$rbpexAfter = Get-RbpexFileStats
$pageServerFileDelta = [pscustomobject][ordered]@{
    Reads = $pageServerAfter.Reads - $pageServerBefore.Reads
    BytesRead = $pageServerAfter.BytesRead - $pageServerBefore.BytesRead
    ReadStallMs = $pageServerAfter.ReadStallMs - $pageServerBefore.ReadStallMs
}
$rbpexFileDelta = [pscustomobject][ordered]@{
    Reads = $rbpexAfter.Reads - $rbpexBefore.Reads
    BytesRead = $rbpexAfter.BytesRead - $rbpexBefore.BytesRead
    ReadStallMs = $rbpexAfter.ReadStallMs - $rbpexBefore.ReadStallMs
}

Write-Host ''
Write-Host 'Running the database drill-down...' -ForegroundColor Yellow
& $sqlcmdPath -S $Server -d $Database -G -C -b -W -i $drilldown -o $drilldownOutput
if ($LASTEXITCODE -ne 0) {
    throw "The database drill-down failed. Read $drilldownOutput."
}

$sessionSummary = foreach ($number in 1..3) {
    $path = Join-Path $OutputDirectory "session-$number.txt"
    $raw = Get-Content -LiteralPath $path -Raw
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

    [pscustomobject][ordered]@{
        Session = $number
        QueryCpuMs = if ($timing) { [int64]$timing.Groups['cpu'].Value } else { $null }
        QueryElapsedMs = if ($timing) { [int64]$timing.Groups['elapsed'].Value } else { $null }
        LogicalReads = if ($io.Success) { [int64]$io.Groups['logical'].Value } else { $null }
        PageServerReads = if ($io.Success) { [int64]$io.Groups['pageServer'].Value } else { $null }
        PageServerReadAhead = if ($io.Success) { [int64]$io.Groups['pageServerReadAhead'].Value } else { $null }
        Output = $path
    }
}

$pageServerPages = ($sessionSummary | Measure-Object -Property PageServerReads -Sum).Sum +
    ($sessionSummary | Measure-Object -Property PageServerReadAhead -Sum).Sum
$rbpexObserved = $rbpexFileDelta.Reads -gt 0
$pageServerObserved = $pageServerFileDelta.Reads -gt 0 -or $pageServerPages -gt 0
$cacheResult = if ($rbpexObserved -and $pageServerObserved) {
    'Both RBPEX and page-server reads were observed after clean buffer-pool pages were removed.'
} elseif ($pageServerObserved) {
    'Page-server reads were observed after clean buffer-pool pages were removed.'
} elseif ($rbpexObserved) {
    'RBPEX reads were observed after clean buffer-pool pages were removed; no page-server reads were observed.'
} else {
    'No RBPEX or page-server read delta was observed; report the measured counters without inferring a source.'
}

Write-Host 'Retrieving Azure Monitor metrics...' -ForegroundColor Yellow
$logicalServer = ($Server -split '\.')[0]
$subscriptions = @(& $az account list --query "[?state=='Enabled'].id" -o tsv) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$managementToken = & $az account get-access-token `
    --resource https://management.azure.com/ `
    --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($managementToken)) {
    throw 'Could not obtain an Azure management token for resource discovery.'
}
$resourceGraphQuery = @"
resources
| where type =~ 'microsoft.sql/servers/databases'
| where name =~ '$Database'
| where id endswith '/servers/$logicalServer/databases/$Database'
| project id, subscriptionId
"@
$resourceGraphBody = @{
    subscriptions = $subscriptions
    query = $resourceGraphQuery
    options = @{ resultFormat = 'objectArray' }
} | ConvertTo-Json -Depth 4
$resourceGraphResult = Invoke-RestMethod `
    -Method Post `
    -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
    -Headers @{ Authorization = "Bearer $managementToken" } `
    -ContentType 'application/json' `
    -Body $resourceGraphBody
$resource = @($resourceGraphResult.data) | Select-Object -First 1
if (-not $resource) {
    throw "Could not find the Azure resource for $logicalServer/$Database in the subscriptions visible to Azure CLI."
}
$resourceId = $resource.id
$subscriptionId = $resource.subscriptionId

$metricsStart = $startedAtUtc.AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ssZ')
$metricsEnd = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$metricJson = & $az monitor metrics list `
    --subscription $subscriptionId `
    --resource $resourceId `
    --metrics cpu_percent physical_data_read_percent log_write_percent `
    --aggregation Average Maximum `
    --interval PT1M `
    --start-time $metricsStart `
    --end-time $metricsEnd `
    --query "value[].{Metric:name.value,Points:timeseries[0].data[].{Time:timeStamp,Average:average,Maximum:maximum}}" `
    -o json
if ($LASTEXITCODE -ne 0) {
    throw 'Azure Monitor metric retrieval failed.'
}
$metricText = $metricJson -join [Environment]::NewLine
$metricText | Set-Content -LiteralPath $metricsOutput -Encoding utf8NoBOM
$metricData = $metricText | ConvertFrom-Json
$metricPoints = @($metricData | ForEach-Object { $_.Points }).Count

$runSummary = [pscustomobject][ordered]@{
    InvestigationWindowUtc = [ordered]@{
        Start = $startedAtUtc.ToString('o')
        End = $finishedAtUtc.ToString('o')
    }
    Sessions = $sessionSummary
    TotalPageServerPages = $pageServerPages
    RbpexVirtualFileDelta = $rbpexFileDelta
    PageServerVirtualFileDelta = $pageServerFileDelta
    CacheResult = $cacheResult
    AzureMonitorMetricPointCount = $metricPoints
    DrilldownOutput = $drilldownOutput
    AzureMonitorOutput = $metricsOutput
}
$runSummary | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $summaryOutput -Encoding utf8NoBOM

Write-Host ''
Write-Host 'Investigation complete.' -ForegroundColor Green
Write-Host ("UTC window : {0:yyyy-MM-dd HH:mm:ss} through {1:yyyy-MM-dd HH:mm:ss}" -f $startedAtUtc, $finishedAtUtc) -ForegroundColor Green
Write-Host "Cache result: $cacheResult" -ForegroundColor Green
Write-Host ("RBPEX virtual-file delta: {0:N0} reads, {1:N0} bytes, {2:N0} ms read stall" -f `
    $rbpexFileDelta.Reads, $rbpexFileDelta.BytesRead, $rbpexFileDelta.ReadStallMs) -ForegroundColor Green
Write-Host ("Page-server virtual-file delta: {0:N0} reads, {1:N0} bytes, {2:N0} ms read stall" -f `
    $pageServerFileDelta.Reads, $pageServerFileDelta.BytesRead, $pageServerFileDelta.ReadStallMs) -ForegroundColor Green
Write-Host "Summary     : $summaryOutput" -ForegroundColor Gray
Write-Host "Drill-down  : $drilldownOutput" -ForegroundColor Gray
Write-Host "Metrics     : $metricsOutput" -ForegroundColor Gray
