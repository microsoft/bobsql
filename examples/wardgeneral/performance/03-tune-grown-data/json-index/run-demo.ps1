<#
.SYNOPSIS
    Runs the Ward General JSON-index demo and saves before/after actual plans.

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
$beforeScript = Join-Path $PSScriptRoot '02-before.sql'
$indexScript = Join-Path $PSScriptRoot '03-create-index.sql'
$afterScript = Join-Path $PSScriptRoot '04-after.sql'
$cleanupScript = Join-Path $PSScriptRoot '05-cleanup.sql'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$runDirectory = Join-Path $PSScriptRoot "results\runs\$runId"

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

function Get-TargetPlan {
    param([Parameter(Mandatory)] [string] $OutputPath)

    $rawOutput = Get-Content -LiteralPath $OutputPath -Raw
    $planMatches = [regex]::Matches(
        $rawOutput,
        '<ShowPlanXML\b.*?</ShowPlanXML>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($match in $planMatches) {
        [xml] $plan = $match.Value
        $namespace = [System.Xml.XmlNamespaceManager]::new($plan.NameTable)
        $namespace.AddNamespace('sp', $plan.DocumentElement.NamespaceURI)
        $statement = $plan.SelectSingleNode(
            "//sp:StmtSimple[contains(@StatementText, 'JSON_CONTAINS')]",
            $namespace)
        if ($statement) { return $match.Value }
    }

    throw "No JSON_CONTAINS actual plan was found in $OutputPath."
}

function Get-AncestorRelOp {
    param([System.Xml.XmlNode] $Node)

    $current = $Node
    while ($current -and $current.LocalName -ne 'RelOp') {
        $current = $current.ParentNode
    }
    return $current
}

function Get-PlanEvidence {
    param(
        [Parameter(Mandatory)] [string] $Phase,
        [Parameter(Mandatory)] [string] $PlanPath
    )

    [xml] $plan = Get-Content -LiteralPath $PlanPath -Raw
    $namespace = [System.Xml.XmlNamespaceManager]::new($plan.NameTable)
    $namespace.AddNamespace('sp', $plan.DocumentElement.NamespaceURI)
    $statement = $plan.SelectSingleNode(
        "//sp:StmtSimple[contains(@StatementText, 'JSON_CONTAINS')]",
        $namespace)

    $jsonObject = $statement.SelectSingleNode(".//sp:Object[@IndexKind='Json']", $namespace)
    $baseObject = $statement.SelectSingleNode(
        ".//sp:Object[@Schema='[clinical]' and @Table='[LabResultArchive]']",
        $namespace)
    $accessObject = if ($jsonObject) { $jsonObject } else { $baseObject }
    $accessOperator = Get-AncestorRelOp -Node $accessObject
    $runtime = $accessOperator.SelectSingleNode(
        './/sp:RunTimeCountersPerThread[@Thread="0"]',
        $namespace)

    [pscustomobject]@{
        Phase = $Phase
        PlanFile = Split-Path $PlanPath -Leaf
        PhysicalOperator = Get-AttributeValue -Node $accessOperator -Name 'PhysicalOp'
        JsonIndexAccess = [bool] $jsonObject
        IndexKind = Get-AttributeValue -Node $accessObject -Name 'IndexKind'
        Table = Get-AttributeValue -Node $accessObject -Name 'Table'
        Index = Get-AttributeValue -Node $accessObject -Name 'Index'
        EstimatedRows = Get-AttributeValue -Node $accessOperator -Name 'EstimateRows'
        ActualRows = Get-AttributeValue -Node $runtime -Name 'ActualRows'
    }
}

Write-Host 'Performance Demo 3: JSON index before and after' -ForegroundColor Cyan
Write-Host ("  Target database {0} @ {1}" -f $Database, $Server)
Write-Host '  Creates 5,000,005 demo-owned rows.'
Write-Host '  CREATE JSON INDEX is offline and can block access to the demo archive while it runs.' -ForegroundColor Yellow
Write-Host '  Saves before-index.sqlplan and after-index.sqlplan, then removes all demo objects.'

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview only. Rerun with -Execute to approve the offline build and run the demo.' -ForegroundColor Yellow
    return
}

New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$beforeOutputPath = Join-Path $runDirectory 'before-output.txt'
$indexOutputPath = Join-Path $runDirectory 'index-build-output.txt'
$afterOutputPath = Join-Path $runDirectory 'after-output.txt'
$beforePlanPath = Join-Path $runDirectory 'before-index.sqlplan'
$afterPlanPath = Join-Path $runDirectory 'after-index.sqlplan'

try {
    Invoke-SqlScript -Script $cleanupScript
    Invoke-SqlScript -Script $setupScript
    Invoke-SqlScript -Script $beforeScript -OutputPath $beforeOutputPath

    $beforePlan = Get-TargetPlan -OutputPath $beforeOutputPath
    [System.IO.File]::WriteAllText(
        $beforePlanPath,
        $beforePlan,
        [System.Text.UTF8Encoding]::new($false))

    Invoke-SqlScript -Script $indexScript -OutputPath $indexOutputPath
    Invoke-SqlScript -Script $afterScript -OutputPath $afterOutputPath

    $afterPlan = Get-TargetPlan -OutputPath $afterOutputPath
    [System.IO.File]::WriteAllText(
        $afterPlanPath,
        $afterPlan,
        [System.Text.UTF8Encoding]::new($false))

    $planEvidence = @(
        Get-PlanEvidence -Phase 'Before index' -PlanPath $beforePlanPath
        Get-PlanEvidence -Phase 'After index' -PlanPath $afterPlanPath
    )
    $summaryPath = Join-Path $runDirectory 'plan-summary.csv'
    $planEvidence | Export-Csv -LiteralPath $summaryPath -NoTypeInformation

    Write-Host ''
    Write-Host 'Actual-plan evidence' -ForegroundColor Green
    foreach ($evidence in $planEvidence) {
        Write-Host ("  {0}: Operator={1}; JsonIndexAccess={2}; IndexKind={3}; Index={4}; ActualRows={5}" -f
            $evidence.Phase,
            $evidence.PhysicalOperator,
            $evidence.JsonIndexAccess,
            $(if ($evidence.IndexKind) { $evidence.IndexKind } else { 'none' }),
            $(if ($evidence.Index) { $evidence.Index } else { 'none' }),
            $evidence.ActualRows)
    }
    Write-Host ("Results: {0}" -f $runDirectory)
}
finally {
    Invoke-SqlScript -Script $cleanupScript
}