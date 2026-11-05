<#
.SYNOPSIS
    Collect bounded control-plane, replica, and metric evidence after failover.

.DESCRIPTION
    Uses the supplied UTC interval to query the exact Ward General database's
    Azure Activity Log and Azure Monitor metrics, then reuses Observability's
    read-only availability SQL for a post-failover replica snapshot. Evidence
    is written to a timestamped temporary directory. Azure delivery can lag;
    an empty bounded result is reported as unavailable, not as zero.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [DateTimeOffset] $StartUtc,
    [Parameter(Mandatory)]
    [DateTimeOffset] $EndUtc,
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd,
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($EndUtc -le $StartUtc) { throw 'EndUtc must be later than StartUtc.' }

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No Ward General server is configured.'
}

$logicalServer = $Server -replace '\.database\.windows\.net$', ''
$account = az account show --query '{name:name, id:id}' --output json | ConvertFrom-Json
$resource = az sql db show `
    --resource-group $ResourceGroup `
    --server $logicalServer `
    --name $Database `
    --query '{id:id, edition:edition, location:location}' `
    --output json | ConvertFrom-Json
if ($resource.edition -ne 'Hyperscale') {
    throw "Database '$Database' is '$($resource.edition)', not Hyperscale."
}

if (-not $OutputDirectory) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) "wardgeneral-ha-resiliency-failover-$stamp"
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

$windowStart = $StartUtc.ToUniversalTime().AddMinutes(-5)
$windowEnd = $EndUtc.ToUniversalTime().AddMinutes(5)
$startText = $windowStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
$endText = $windowEnd.ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Host '--- High Availability and Resiliency failover evidence ---'
Write-Host "Subscription : $($account.name) ($($account.id))"
Write-Host "Resource ID  : $($resource.id)"
Write-Host "Run interval : $($StartUtc.ToUniversalTime().ToString('O')) through $($EndUtc.ToUniversalTime().ToString('O'))"
Write-Host "Query window : $startText through $endText (five-minute delivery guard)"
Write-Host "Evidence     : $OutputDirectory"

Write-Host ''
Write-Host '=== Azure Activity Log ==='
$activity = @(az monitor activity-log list `
    --resource-id $resource.id `
    --start-time $startText `
    --end-time $endText `
    --max-events 100 `
    --output json | ConvertFrom-Json)
$activityPath = Join-Path $OutputDirectory 'activity-log.json'
ConvertTo-Json -InputObject $activity -Depth 20 |
    Set-Content -LiteralPath $activityPath -Encoding utf8NoBOM
if ($activity.Count -eq 0) {
    Write-Host 'No Activity Log events have been delivered for the bounded window.' -ForegroundColor Yellow
}
else {
    $activity | Select-Object `
        @{ Name = 'TimeUtc'; Expression = { $_.eventTimestamp } }, `
        @{ Name = 'Operation'; Expression = { $_.operationName.localizedValue } }, `
        @{ Name = 'Status'; Expression = { $_.status.value } }, `
        correlationId | Format-Table -AutoSize | Out-String | Write-Host
}

Write-Host '=== Post-failover replica snapshot ==='
$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sqlcmdPath) {
    throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd'
}
$availabilitySql = Join-Path $PSScriptRoot '..' '..' 'observability' 'availability' 'availability.sql'
$replicaOutput = & $sqlcmdPath -S $Server -d $Database -G -C -b -i $availabilitySql 2>&1
if ($LASTEXITCODE -ne 0) { throw "Replica snapshot failed with exit code $LASTEXITCODE." }
$replicaOutput | Write-Host
$replicaOutput | Set-Content -LiteralPath (Join-Path $OutputDirectory 'replica-snapshot.txt') -Encoding utf8NoBOM

Write-Host ''
Write-Host '=== Azure Monitor ==='
$metricArguments = @(
    'monitor', 'metrics', 'list',
    '--subscription', $account.id,
    '--resource', $resource.id,
    '--interval', 'PT1M',
    '--start-time', $startText,
    '--end-time', $endText,
    '--output', 'json'
)
$availabilityMetrics = az @metricArguments `
    --metrics availability `
    --aggregation Average Minimum | ConvertFrom-Json
$connectionMetrics = az @metricArguments `
    --metrics connection_successful connection_failed connection_failed_user_error blocked_by_firewall `
    --aggregation Total | ConvertFrom-Json
$replicationMetrics = az @metricArguments `
    --metrics replication_lag_seconds `
    --aggregation Average Maximum | ConvertFrom-Json

$metricEvidence = [pscustomobject][ordered]@{
    ResourceId = $resource.id
    RunStartUtc = $StartUtc.ToUniversalTime().ToString('O')
    RunEndUtc = $EndUtc.ToUniversalTime().ToString('O')
    QueryStartUtc = $windowStart.ToString('O')
    QueryEndUtc = $windowEnd.ToString('O')
    Metrics = @(
        $availabilityMetrics.value
        $connectionMetrics.value
        $replicationMetrics.value
    )
}
$metricsPath = Join-Path $OutputDirectory 'azure-monitor.json'
$metricEvidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metricsPath -Encoding utf8NoBOM

$metricDelivery = foreach ($metric in $metricEvidence.Metrics) {
    $points = @($metric.timeseries | ForEach-Object { $_.data })
    $returned = @($points | Where-Object {
        $point = $_
        $hasValue = $false
        foreach ($propertyName in @('average', 'minimum', 'maximum', 'total')) {
            $property = $point.PSObject.Properties[$propertyName]
            if ($property -and $null -ne $property.Value) {
                $hasValue = $true
                break
            }
        }
        $hasValue
    }).Count
    [pscustomobject]@{
        Metric = $metric.name.value
        ReturnedPoints = $returned
        Delivery = if ($returned -gt 0) { 'Values returned' } else { 'No values returned' }
    }
}
$metricDelivery | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "ActivityLogEvidence=$activityPath"
Write-Host "ReplicaEvidence=$(Join-Path $OutputDirectory 'replica-snapshot.txt')"
Write-Host "AzureMonitorEvidence=$metricsPath"
