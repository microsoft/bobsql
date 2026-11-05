<#
.SYNOPSIS
    Runs a five-minute Ward General growth workload and captures its performance.

.EXAMPLE
    ./run-demo.ps1
    ./run-demo.ps1 -Execute
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [ValidateRange(30, 600)]
    [int] $WorkloadSeconds = 300,
    [int] $SampleSeconds = 15,
    [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($SampleSeconds -lt 5) {
    throw 'SampleSeconds must be at least 5.'
}

$loadEnv = Join-Path $PSScriptRoot '..\..\first-app\load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database }
if ([string]::IsNullOrWhiteSpace($Server) -or [string]::IsNullOrWhiteSpace($Database)) {
    throw 'Configure WardGeneral__Server and WardGeneral__Database or pass -Server and -Database.'
}

$sqlcmd = @(
    $env:SQLCMD,
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sqlcmd) {
    throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd'
}
$sqlsim = @(
    $env:SQLSIM
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sqlsim) {
    throw 'Set SQLSIM to the full path of sqlsim.exe from https://aka.ms/sqlsimtools.'
}

$snapshotScript = Join-Path $PSScriptRoot 'capture-growth-io.sql'
$sampleScript = Join-Path $PSScriptRoot 'sample-growth-io.sql'
$workloadTemplate = Join-Path $PSScriptRoot 'growth-workload.json'
$reportScript = Join-Path $PSScriptRoot 'build-growth-report.ps1'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$runDirectory = Join-Path $PSScriptRoot "results\runs\$runId"
$timelineDirectory = Join-Path $runDirectory 'timeline'

function Invoke-SqlCapture {
    param(
        [Parameter(Mandatory)] [string] $Script,
        [Parameter(Mandatory)] [string] $OutputPath,
        [string] $VariableName,
        [string] $VariableValue
    )

    $arguments = @(
        '-S', $Server,
        '-d', $Database,
        '-G',
        '-b',
        '-W',
        '-h', '-1',
        '-i', $Script,
        '-o', $OutputPath
    )
    if ($VariableName) {
        $arguments += @('-v', "$VariableName=$VariableValue")
    }
    & $sqlcmd @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for $Script with exit code $LASTEXITCODE."
    }
}

$previewDirectory = Join-Path $PSScriptRoot 'results\preview'
New-Item -ItemType Directory -Path $previewDirectory -Force | Out-Null
$previewPath = Join-Path $previewDirectory 'current.txt'
Invoke-SqlCapture -Script $snapshotScript -OutputPath $previewPath `
    -VariableName SnapshotName -VariableValue Preview

$metaLine = Get-Content -LiteralPath $previewPath |
    Where-Object { $_.StartsWith('META|') } |
    Select-Object -First 1
if (-not $metaLine) { throw 'The preview snapshot did not return a META record.' }
$meta = $metaLine -split '\|'
$currentReservedGB = [double]::Parse(
    $meta[5], [System.Globalization.CultureInfo]::InvariantCulture)
$serviceObjective = $meta[4]

Write-Host 'Performance Demo 2: grow data and find the constraint' -ForegroundColor Cyan
Write-Host ("  Target database  {0} @ {1}" -f $Database, $Server)
Write-Host ("  Service objective {0}" -f $serviceObjective)
Write-Host ("  Current reserved  {0:N2} GB" -f $currentReservedGB)
Write-Host ("  Workload interval {0} seconds" -f $WorkloadSeconds)
Write-Host ("  Sample interval   {0} seconds" -f $SampleSeconds)

if ($serviceObjective -ne 'HS_Gen5_40') {
    throw "Demo 2 requires HS_Gen5_40; the database reports $serviceObjective."
}
if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview only. This exercise runs one write-intensive interval and permanently appends its generated data.' -ForegroundColor Yellow
    Write-Host 'Rerun with -Execute to start the workload and automatic report capture.' -ForegroundColor Yellow
    return
}

New-Item -ItemType Directory -Path $timelineDirectory -Force | Out-Null
$beforePath = Join-Path $runDirectory 'before.txt'
$afterPath = Join-Path $runDirectory 'after.txt'
$metadataPath = Join-Path $runDirectory 'run-metadata.json'
$startedAtUtc = (Get-Date).ToUniversalTime()
$workloadDefinition = Get-Content -LiteralPath $workloadTemplate -Raw | ConvertFrom-Json
if ([int]$workloadDefinition.duration_seconds -ne $WorkloadSeconds) {
    throw "WorkloadSeconds must match growth-workload.json ($($workloadDefinition.duration_seconds) seconds)."
}

$metadata = [ordered]@{
    runId = $runId
    server = $Server
    database = $Database
    serviceObjective = $serviceObjective
    workloadSeconds = $WorkloadSeconds
    sampleSeconds = $SampleSeconds
    startedAtUtc = $startedAtUtc.ToString('o')
    endedAtUtc = $null
    workloadExitCode = $null
    intervals = @()
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding utf8

Copy-Item -LiteralPath $previewPath -Destination $beforePath

Write-Host ''
Write-Host ("Growth started at {0:u}." -f $startedAtUtc) -ForegroundColor Cyan
$sampleNumber = 0
$reservedGB = $currentReservedGB
$process = $null
try {
    foreach ($intervalNumber in 1) {
        $intervalName = 'Interval{0:D3}' -f $intervalNumber
        $intervalOutput = Join-Path $runDirectory "$intervalName-sqlsim.txt"
        $intervalConsole = Join-Path $runDirectory "$intervalName-console.txt"
        $intervalError = Join-Path $runDirectory "$intervalName-error.txt"
        $intervalStartedAtUtc = (Get-Date).ToUniversalTime()

        $token = az account get-access-token `
            --resource https://database.windows.net/ `
            --query accessToken `
            --output tsv
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'Azure CLI returned an empty Azure SQL access token.'
        }

        $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $processInfo.FileName = $sqlsim
        $processInfo.WorkingDirectory = $PSScriptRoot
        foreach ($argument in @(
            '-S', $Server,
            '-d', $Database,
            '-T', $token,
            '-workload', $workloadTemplate,
            '-retry', '3',
            '-retrydelay', '5',
            '-t', '240',
            '-q',
            '-o', $intervalOutput
        )) {
            [void]$processInfo.ArgumentList.Add($argument)
        }
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $processInfo
        if (-not $process.Start()) { throw 'The sqlsim workload process did not start.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $token = $null

        Write-Host ("--- {0}: 64 writers for {1} seconds ---" -f $intervalName, $WorkloadSeconds) -ForegroundColor Cyan
        while (-not $process.WaitForExit($SampleSeconds * 1000)) {
            $sampleNumber++
            $sampleName = 'Sample{0:D5}' -f $sampleNumber
            $samplePath = Join-Path $timelineDirectory "$sampleName.txt"
            Invoke-SqlCapture -Script $sampleScript -OutputPath $samplePath `
                -VariableName SampleName -VariableValue $sampleName

            $sampleLine = Get-Content -LiteralPath $samplePath |
                Where-Object { $_.StartsWith('SAMPLE|') } |
                Select-Object -First 1
            $resourceLine = Get-Content -LiteralPath $samplePath |
                Where-Object { $_.StartsWith('RESOURCE|') } |
                Select-Object -First 1
            if ($sampleLine) {
                $sample = $sampleLine -split '\|'
                $reservedGB = [double]::Parse(
                    $sample[3], [System.Globalization.CultureInfo]::InvariantCulture)
                $growthGB = $reservedGB - $currentReservedGB
                $logWrite = if ($resourceLine) { ($resourceLine -split '\|')[5] } else { 'n/a' }
                Write-Host ("  {0:u}  {1,8:N2} GB added  log {2}%" -f
                    (Get-Date).ToUniversalTime(), $growthGB, $logWrite)
            }
        }

        $process.WaitForExit()
        $stdoutTask.GetAwaiter().GetResult() |
            Set-Content -LiteralPath $intervalConsole -Encoding utf8
        $stderrTask.GetAwaiter().GetResult() |
            Set-Content -LiteralPath $intervalError -Encoding utf8
        if ($process.ExitCode -ne 0) {
            throw "sqlsim interval $intervalNumber failed with exit code $($process.ExitCode)."
        }

        $sampleNumber++
        $sampleName = 'Sample{0:D5}' -f $sampleNumber
        $samplePath = Join-Path $timelineDirectory "$sampleName.txt"
        Invoke-SqlCapture -Script $sampleScript -OutputPath $samplePath `
            -VariableName SampleName -VariableValue $sampleName
        $sampleLine = Get-Content -LiteralPath $samplePath |
            Where-Object { $_.StartsWith('SAMPLE|') } |
            Select-Object -First 1
        if (-not $sampleLine) { throw 'The interval-end sample did not return a SAMPLE record.' }
        $reservedGB = [double]::Parse(
            (($sampleLine -split '\|')[3]),
            [System.Globalization.CultureInfo]::InvariantCulture)

        $metadata.intervals += [ordered]@{
            interval = $intervalNumber
            startedAtUtc = $intervalStartedAtUtc.ToString('o')
            endedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            reservedGB = $reservedGB
        }
        $metadata | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $metadataPath -Encoding utf8
        $process.Dispose()
        $process = $null
    }
}
finally {
    $token = $null
    if ($process -and -not $process.HasExited) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    if ($process) { $process.Dispose() }
}

$metadata.endedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$metadata.workloadExitCode = 0
$metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding utf8

Invoke-SqlCapture -Script $snapshotScript -OutputPath $afterPath `
    -VariableName SnapshotName -VariableValue After

& $reportScript -RunDirectory $runDirectory

Write-Host ''
Write-Host 'Demo 2 growth and report capture complete.' -ForegroundColor Green
Write-Host ("  Evidence and report  {0}" -f $runDirectory)