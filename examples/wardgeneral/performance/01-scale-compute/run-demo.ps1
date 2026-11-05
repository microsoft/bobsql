<#
.SYNOPSIS
    Runs the Performance Stage 1 compute-scale progression.

.DESCRIPTION
    Establishes the workload at HS_Gen5_8, scales to HS_Gen5_16 and repeats,
    then scales to HS_Gen5_40 and repeats. The workload settings remain fixed,
    so compute size is the independent variable.

    Without -ApproveScaling, this script only validates the starting state and
    prints the two billable changes. One explicit approval covers the displayed
    8 -> 16 -> 40 plan. The script never scales the database back down.

.EXAMPLE
    ./run-demo.ps1 -ResourceGroup rg-collierhealth

.EXAMPLE
    ./run-demo.ps1 -ResourceGroup rg-collierhealth -ApproveScaling
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ResourceGroup = $env:RG,

    [switch] $ResetDemoData,

    [switch] $ApproveCleanup,

    [switch] $ApproveScaling
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    throw 'Set RG or pass -ResourceGroup.'
}

& (Join-Path $PSScriptRoot 'preflight.ps1') `
    -ResourceGroup $ResourceGroup `
    -ResetDemoData:$ResetDemoData `
    -ApproveCleanup:$ApproveCleanup

$loadEnv = Join-Path $PSScriptRoot '..\..\first-app\load-env.ps1'
. $loadEnv -Require @('WardGeneral__Server', 'WardGeneral__Database') -Quiet

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install it, run az login, and retry.'
}

$serverName = ($env:WardGeneral__Server).Split('.')[0]
$database = $env:WardGeneral__Database
$steps = @('HS_Gen5_8', 'HS_Gen5_16', 'HS_Gen5_40')
$workloads = @{
    'HS_Gen5_8' = Join-Path $PSScriptRoot 'workload-8.json'
    'HS_Gen5_16' = Join-Path $PSScriptRoot 'workload-16.json'
    'HS_Gen5_40' = Join-Path $PSScriptRoot 'workload-40.json'
}
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$outputDirectory = Join-Path $PSScriptRoot "results\runs\$runId"
$metadataPath = Join-Path $outputDirectory 'run-metadata.json'
$runMetadata = [ordered]@{
    runId = $runId
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    database = $database
    phases = @()
}

function Get-CurrentServiceObjective {
    az sql db show `
        --resource-group $ResourceGroup `
        --server $serverName `
        --name $database `
        --query currentServiceObjectiveName `
        --output tsv
}

$current = Get-CurrentServiceObjective

Write-Host 'Performance Stage 1: scale compute under load' -ForegroundColor Cyan
Write-Host ("  Database     {0} @ {1}" -f $database, $serverName)
Write-Host ("  Current      {0}" -f $current)
Write-Host ("  Progression  {0}" -f ($steps -join ' -> '))
Write-Host '  Workload     100 -> 200 -> 400 threads; 90 seconds at each size'
Write-Host ("  Final state  HS_Gen5_40; no automatic scale-down")

if ($current -ne $steps[0]) {
    throw "Stage 1 must begin at $($steps[0]); the database is currently $current. No change was made."
}

if (-not $ApproveScaling) {
    Write-Host ''
    Write-Host 'Preview only. This plan contains two billable Azure changes:' -ForegroundColor Yellow
    Write-Host '  1. HS_Gen5_8  -> HS_Gen5_16' -ForegroundColor Yellow
    Write-Host '  2. HS_Gen5_16 -> HS_Gen5_40' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Re-run with -ApproveScaling to authorize both displayed changes.' -ForegroundColor Yellow
    return
}

if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
$runMetadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding utf8

foreach ($index in 0..($steps.Count - 1)) {
    $serviceObjective = $steps[$index]
    $current = Get-CurrentServiceObjective
    if ($current -ne $serviceObjective) {
        throw "Expected $serviceObjective before its workload interval; Azure reports $current."
    }

    Write-Host ''
    Write-Host ("--- Workload at {0} ---" -f $serviceObjective) -ForegroundColor Cyan
    $phaseName = $serviceObjective.ToLowerInvariant()
    $workloadDefinition = Get-Content -LiteralPath $workloads[$serviceObjective] -Raw | ConvertFrom-Json
    $phaseStartedAtUtc = (Get-Date).ToUniversalTime()
    $beforeNetwork = & (Join-Path $PSScriptRoot 'network-probe.ps1') `
        -OutputPath (Join-Path $outputDirectory ("network-{0}-before.json" -f $phaseName))
    & (Join-Path $PSScriptRoot 'capture-server.ps1') `
        -OutputPath (Join-Path $outputDirectory ("server-{0}-before.txt" -f $phaseName))

    $outputPath = Join-Path $outputDirectory ("sqlsim-{0}.txt" -f $serviceObjective.ToLowerInvariant())
    & (Join-Path $PSScriptRoot 'run-workload.ps1') `
        -WorkloadPath $workloads[$serviceObjective] `
        -OutputPath $outputPath

    & (Join-Path $PSScriptRoot 'capture-server.ps1') `
        -OutputPath (Join-Path $outputDirectory ("server-{0}-after.txt" -f $phaseName))
    $afterNetwork = & (Join-Path $PSScriptRoot 'network-probe.ps1') `
        -OutputPath (Join-Path $outputDirectory ("network-{0}-after.json" -f $phaseName))
    $phaseEndedAtUtc = (Get-Date).ToUniversalTime()

    $runMetadata.phases += [ordered]@{
        serviceObjective = $serviceObjective
        users = ($workloadDefinition.workloads | Measure-Object -Property threads -Sum).Sum
        durationSeconds = $workloadDefinition.duration_seconds
        startedAtUtc = $phaseStartedAtUtc.ToString('o')
        endedAtUtc = $phaseEndedAtUtc.ToString('o')
    }
    $runMetadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding utf8

    $networkChangePercent = 100.0 *
        ($afterNetwork.AverageQueryMs - $beforeNetwork.AverageQueryMs) /
        [Math]::Max($beforeNetwork.AverageQueryMs, 0.001)
    Write-Host ("Network control: {0:N2} ms before; {1:N2} ms after ({2:+0.0;-0.0;0.0}%)." -f
        $beforeNetwork.AverageQueryMs,
        $afterNetwork.AverageQueryMs,
        $networkChangePercent)
    if ([Math]::Abs($networkChangePercent) -gt 25.0) {
        Write-Warning 'Network control shifted by more than 25%; repeat this phase before comparing laptop latency.'
    }

    if ($index -eq $steps.Count - 1) { break }

    $target = $steps[$index + 1]
    Write-Host ''
    Write-Host ("--- Scale to {0} ---" -f $target) -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'scale-compute.ps1') `
        -ResourceGroup $ResourceGroup `
        -TargetServiceObjective $target `
        -Approve
}

Write-Host ''
Write-Host 'Stage 1 complete.' -ForegroundColor Green
Write-Host 'The database remains at HS_Gen5_40 for Stage 2.' -ForegroundColor Green
& (Join-Path $PSScriptRoot 'summarize-run.ps1') -RunDirectory $outputDirectory
Write-Host ("Evidence and report: {0}" -f $outputDirectory)
