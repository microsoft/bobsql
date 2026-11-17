[CmdletBinding()]
param(
    [string] $EnvironmentName = 'caldova-evidence',
    [string] $HostedAgentName = 'caldova-evidence-hosted'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

$hostedProject = Join-Path $PSScriptRoot '..\agent\hosted\caldova-evidence-hosted'
$firstPrompt = 'How might intestinal microbiome disruption influence anxiety and depression?'
$followUpPrompt = 'Which of those three studies gives the strongest causal evidence, and why?'

function Invoke-Azd {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $env:AZURE_DEV_USER_AGENT = 'microsoft_foundry_skill'
    $output = & azd @Arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Text = ($output | Out-String)
    }
}

function Get-MatchValue {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string[]] $Patterns
    )

    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Text, $pattern, 'IgnoreCase')
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return $null
}

function Get-PmcIds {
    param([Parameter(Mandatory)][string] $Text)
    return @([regex]::Matches($Text, 'PMC\d+') | ForEach-Object Value | Sort-Object -Unique)
}

function Get-AssistantText {
    param([Parameter(Mandatory)][string] $Text)

    $decoded = @([regex]::Matches($Text, '"type":"response\.output_text\.done"[^\r\n]*?"text":"((?:\\.|[^"\\])*)"') | ForEach-Object {
        try { '"' + $_.Groups[1].Value + '"' | ConvertFrom-Json } catch { $null }
    })
    $answer = $decoded | Sort-Object Length -Descending | Select-Object -First 1
    if (-not $answer) { throw 'Could not extract the final assistant response.' }
    return $answer
}

function Invoke-FirstTurn {
    $arguments = @(
        '--cwd', $hostedProject, 'ai', 'agent', 'invoke', $HostedAgentName,
        '--protocol', 'responses', '--version', $version, '--new-session', '--new-conversation',
        '--output', 'raw', '--timeout', '0', '--environment', $EnvironmentName, $firstPrompt
    )

    $result = Invoke-Azd $arguments
    if ($result.ExitCode -eq 0) { return $result }

    if ($result.Text -notmatch 'session_not_ready') {
        throw "Hosted turn one failed.`n$($result.Text)"
    }

    $sessionId = Get-MatchValue $result.Text @(
        "Session '([^']+)' did not become ready",
        'X-Agent-Session-Id:\s*([A-Za-z0-9]+)'
    )
    if (-not $sessionId) { throw 'Could not recover the transient hosted session ID.' }

    Write-Warn "Session $sessionId was not ready; retrying the identical request against that session."
    $retryArguments = @(
        '--cwd', $hostedProject, 'ai', 'agent', 'invoke', $HostedAgentName,
        '--protocol', 'responses', '--session-id', $sessionId, '--new-conversation',
        '--output', 'raw', '--timeout', '0', '--environment', $EnvironmentName, $firstPrompt
    )
    $retry = Invoke-Azd $retryArguments
    if ($retry.ExitCode -ne 0) { throw "Hosted turn-one retry failed.`n$($retry.Text)" }
    return $retry
}

Write-Step 'Confirm the active hosted-agent version'
$show = Invoke-Azd @('--cwd', $hostedProject, 'ai', 'agent', 'show', $HostedAgentName, '--output', 'json', '--environment', $EnvironmentName)
if ($show.ExitCode -ne 0) { throw "Could not inspect the hosted agent.`n$($show.Text)" }
$agent = $show.Text | ConvertFrom-Json
if ($agent.status -ne 'active') { throw "Hosted agent status is '$($agent.status)', not active." }
$version = [string]$agent.version
Write-Ok "$HostedAgentName version $version is active"

Write-Step 'Turn 1: fresh Azure session and three-source evidence briefing'
$first = Invoke-FirstTurn
$sessionId = Get-MatchValue $first.Text @(
    'X-Agent-Session-Id:\s*([A-Za-z0-9]+)',
    '"agent_session_id":"([A-Za-z0-9]+)"'
)
$conversationId = Get-MatchValue $first.Text @('"conversation":\{"id":"([^"]+)"')
if (-not $sessionId -or -not $conversationId) { throw 'Turn one did not return hosted session and conversation IDs.' }
if ($first.Text -match 'response\.failed|"status":"failed"') { throw 'Turn one returned a failed response.' }
$searchCalls = @([regex]::Matches($first.Text, '"call_id":"([^"]+)","name":"search_evidence"') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique).Count
if ($searchCalls -ne 3) { throw "Turn one performed $searchCalls search_evidence calls, expected exactly 3." }
$firstAnswer = Get-AssistantText $first.Text
$firstSources = Get-PmcIds $firstAnswer
if ($firstSources.Count -ne 3) { throw "Turn one returned $($firstSources.Count) distinct PMC sources, expected exactly 3." }
$missingHeadings = @(@('## Bottom line', '## Evidence signals', '## Confidence', '## Suggested follow-up') |
    Where-Object { $firstAnswer -notmatch [regex]::Escape($_) })
if ($missingHeadings.Count -gt 0) { throw "Turn one omitted headings: $($missingHeadings -join ', ')." }
if ($firstAnswer -notmatch '(?mi)^## Confidence\s*\r?\nHigh for mechanistic plausibility') {
    throw 'Turn one did not report high confidence for mechanistic plausibility.'
}
$firstWords = @($firstAnswer -split '\s+' | Where-Object { $_ }).Count
if ($firstWords -lt 110 -or $firstWords -gt 150) { throw "Turn one returned $firstWords words, expected 110-150." }
Write-Ok "$searchCalls direct SQL MCP searches; $($firstSources.Count) PMC sources; $firstWords words; session $sessionId"

Write-Step 'Turn 2: causal-evidence follow-up in the same Azure conversation'
$followUpArguments = @(
    '--cwd', $hostedProject, 'ai', 'agent', 'invoke', $HostedAgentName,
    '--protocol', 'responses', '--session-id', $sessionId, '--conversation-id', $conversationId,
    '--output', 'raw', '--timeout', '0', '--environment', $EnvironmentName, $followUpPrompt
)
$followUp = Invoke-Azd $followUpArguments
if ($followUp.ExitCode -ne 0) { throw "Hosted turn two failed.`n$($followUp.Text)" }
if ($followUp.Text -match 'response\.failed|"status":"failed"') { throw 'Turn two returned a failed response.' }
$followUpAnswer = Get-AssistantText $followUp.Text
$followUpWords = @($followUpAnswer -split '\s+' | Where-Object { $_ }).Count
if ($followUpWords -gt 150) { throw "Turn two returned $followUpWords words, exceeding the visual briefing limit." }
$followUpHeadings = @(@('## Bottom line', '## Evidence signals', '## Confidence', '## Suggested follow-up') |
    Where-Object { $followUpAnswer -notmatch [regex]::Escape($_) })
if ($followUpHeadings.Count -gt 0) { throw "Turn two omitted visual headings: $($followUpHeadings -join ', ')." }
$followUpLabels = @('**Strongest**', '**Comparison**', '**Limitation**')
$missingLabels = @($followUpLabels | Where-Object { $followUpAnswer -notmatch [regex]::Escape($_) })
if ($missingLabels.Count -gt 0) { throw "Turn two omitted visual labels: $($missingLabels -join ', ')." }
$followUpSources = Get-PmcIds $followUpAnswer
$retainedSources = @($followUpSources | Where-Object { $_ -in $firstSources })
if ($retainedSources.Count -lt 1) { throw 'Turn two did not retain any source from the initial investigation.' }
Write-Ok "$followUpWords words; retained $($retainedSources.Count) prior sources"

Write-Host "`nHosted agent verification passed." -ForegroundColor Green
Write-Host "Agent:        $HostedAgentName version $version"
Write-Host "Session:      $sessionId"
Write-Host "Conversation: $conversationId"
