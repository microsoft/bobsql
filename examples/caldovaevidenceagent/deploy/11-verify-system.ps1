[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

$baseUrl = "https://$AppServiceName.azurewebsites.net"
$ready = Invoke-RestMethod "$baseUrl/api/agent/readiness" -TimeoutSec 240
if (-not $ready.configured) { throw 'The application does not have a configured hosted agent.' }

$initialPrompt = 'How might intestinal microbiome disruption influence anxiety and depression?'
$initial = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/agent" -ContentType 'application/json' `
    -Body (@{ message = $initialPrompt } | ConvertTo-Json -Compress) -TimeoutSec 600
if ($initial.toolCalls -ne 3) { throw "Expected 3 SQL MCP calls; received $($initial.toolCalls)." }
if (@($initial.sources).Count -ne 3) { throw "Expected 3 sources; received $(@($initial.sources).Count)." }
foreach ($heading in @('## Bottom line', '## Evidence signals', '## Confidence', '## Suggested follow-up')) {
    if ($initial.text -notmatch [regex]::Escape($heading)) { throw "Initial response omitted $heading." }
}
if ($initial.text -notmatch '(?mi)^## Confidence\s*\r?\nHigh for mechanistic plausibility') {
    throw 'Initial response did not report high confidence for mechanistic plausibility.'
}

$followUp = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/agent" -ContentType 'application/json' `
    -Body (@{
        message = 'Which of those three studies gives the strongest causal evidence, and why?'
        sessionId = $initial.sessionId
        responseId = $initial.responseId
    } | ConvertTo-Json -Compress) -TimeoutSec 600
foreach ($label in @('**Strongest**', '**Comparison**', '**Limitation**')) {
    if ($followUp.text -notmatch [regex]::Escape($label)) { throw "Follow-up omitted $label." }
}
if ($followUp.toolCalls -ne 0) { throw 'The retained-evidence follow-up performed an unnecessary MCP search.' }

Write-Host "`nEnd-to-end verification passed." -ForegroundColor Green
Write-Host "Application:  $baseUrl"
Write-Host "Agent:        $($ready.agent) version $($ready.version)"
Write-Host "Initial:      $($initial.toolCalls) SQL MCP calls, $(@($initial.sources).Count) sources"
Write-Host "Follow-up:   visual causal comparison, retained evidence"
