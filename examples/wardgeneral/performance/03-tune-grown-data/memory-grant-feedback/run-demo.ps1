<#
.SYNOPSIS
    Runs the Ward General query-feedback demo and saves actual execution plans.

.EXAMPLE
    ./run-demo.ps1
    ./run-demo.ps1 -Execute
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..\..\..\first-app\load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database }
if ([string]::IsNullOrWhiteSpace($Server) -or
    [string]::IsNullOrWhiteSpace($Database)) {
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

$setupScript = Join-Path $PSScriptRoot '01-setup.sql'
$runScript = Join-Path $PSScriptRoot '02-run.sql'
$cleanupScript = Join-Path $PSScriptRoot '03-cleanup.sql'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$runDirectory = Join-Path $PSScriptRoot "results\runs\$runId"
$rawOutputPath = Join-Path $runDirectory 'run-output.txt'

function Invoke-SqlScript {
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $OutputPath
    )

    $arguments = @(
        '-S', $Server,
        '-d', $Database,
        '-G',
        '-b',
        '-W',
        '-y', '0',
        '-i', $Script
    )
    if ($OutputPath) { $arguments += @('-o', $OutputPath) }

    & $sqlcmd @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for $Script with exit code $LASTEXITCODE."
    }
}

function Get-AttributeValue {
    param(
        [System.Xml.XmlNode] $Node,
        [Parameter(Mandatory)] [string] $Name
    )

    if (-not $Node -or -not $Node.Attributes[$Name]) { return $null }
    return $Node.Attributes[$Name].Value
}

Write-Host 'Performance Demo 3: query-processing feedback' -ForegroundColor Cyan
Write-Host ("  Target database {0} @ {1}" -f $Database, $Server)
Write-Host '  Creates five million demo-owned rows and a covering index.'
Write-Host '  Saves actual plans for executions 1 and 2, then removes all demo objects.'

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview only. Rerun with -Execute to run the experiment.' -ForegroundColor Yellow
    return
}

New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

try {
    Invoke-SqlScript -Script $cleanupScript
    Invoke-SqlScript -Script $setupScript
    Invoke-SqlScript -Script $runScript -OutputPath $rawOutputPath

    $rawOutput = Get-Content -LiteralPath $rawOutputPath -Raw
    $planMatches = [regex]::Matches(
        $rawOutput,
        '<ShowPlanXML\b.*?</ShowPlanXML>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if ($planMatches.Count -lt 2) {
        throw "Expected at least two actual Showplan XML documents; found $($planMatches.Count)."
    }

    $planEvidence = for ($execution = 1; $execution -le 2; $execution++) {
        $planXmlText = $planMatches[$execution - 1].Value
        $planPath = Join-Path $runDirectory "execution-$execution.sqlplan"
        [System.IO.File]::WriteAllText(
            $planPath,
            $planXmlText,
            [System.Text.UTF8Encoding]::new($false))

        [xml] $planXml = $planXmlText
        $namespace = [System.Xml.XmlNamespaceManager]::new($planXml.NameTable)
        $namespace.AddNamespace('sp', $planXml.DocumentElement.NamespaceURI)

        $statement = $planXml.SelectSingleNode(
            "//sp:StmtSimple[contains(@StatementText, 'CHECKSUM_AGG')]",
            $namespace)
        if (-not $statement) {
            throw "Execution $execution plan does not contain the expected statement."
        }

        $memoryGrant = $statement.SelectSingleNode('sp:QueryPlan/sp:MemoryGrantInfo', $namespace)
        $sort = $statement.SelectSingleNode(".//sp:RelOp[@PhysicalOp='Sort']", $namespace)
        $spill = $sort.SelectSingleNode('sp:Warnings/sp:SpillToTempDb', $namespace)
        $runtime = $sort.SelectSingleNode(
            './/sp:RunTimeCountersPerThread[@Thread="0"]',
            $namespace)

        [pscustomobject]@{
            Execution = $execution
            PlanFile = Split-Path $planPath -Leaf
            SortWarning = [bool] $spill
            SpillLevel = Get-AttributeValue -Node $spill -Name 'SpillLevel'
            SpilledThreadCount = Get-AttributeValue -Node $spill -Name 'SpilledThreadCount'
            GrantedMemoryKB = Get-AttributeValue -Node $memoryGrant -Name 'GrantedMemory'
            MaxUsedMemoryKB = Get-AttributeValue -Node $memoryGrant -Name 'MaxUsedMemory'
            LastRequestedMemoryKB = Get-AttributeValue -Node $memoryGrant -Name 'LastRequestedMemory'
            MemoryGrantFeedback = Get-AttributeValue -Node $memoryGrant -Name 'IsMemoryGrantFeedbackAdjusted'
            ActualRows = Get-AttributeValue -Node $runtime -Name 'ActualRows'
        }
    }

    $summaryPath = Join-Path $runDirectory 'plan-summary.csv'
    $planEvidence | Export-Csv -LiteralPath $summaryPath -NoTypeInformation

    Write-Host ''
    Write-Host 'Actual-plan evidence' -ForegroundColor Green
    foreach ($evidence in $planEvidence) {
        Write-Host ("  Execution {0}: SortWarning={1}; SpillLevel={2}; Grant={3:N2} MB; Used={4:N2} MB; MGF={5}; ActualRows={6}" -f
            $evidence.Execution,
            $evidence.SortWarning,
            $(if ($evidence.SpillLevel) { $evidence.SpillLevel } else { 'none' }),
            ([double] $evidence.GrantedMemoryKB / 1024.0),
            ([double] $evidence.MaxUsedMemoryKB / 1024.0),
            $evidence.MemoryGrantFeedback,
            $evidence.ActualRows)
    }
    Write-Host ("Results: {0}" -f $runDirectory)
}
finally {
    Invoke-SqlScript -Script $cleanupScript
}