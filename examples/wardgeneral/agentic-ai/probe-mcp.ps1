#requires -Version 7.0
<#
.SYNOPSIS
    List the MCP tools a running Ward General DAB endpoint publishes.

.DESCRIPTION
    Read the tool inventory BEFORE pointing a model at an endpoint. The tool list
    is the actual security surface of the agent: whatever is on it, the model may
    call, and whatever is not on it cannot be reached no matter what the prompt
    says.

    Agentic AI publishes one endpoint on port 5000 over the wardgeneral primary.
    Reads: get_patient_chart, get_patient_chart_by_bed, search_encounters,
    get_handoff_candidates, search_clinical_context, clinical_assistance.
    Write: save_handoff. It MUST be approval-gated in the app — that is the
    app's job, not DAB's, and this probe cannot verify it.

.EXAMPLE
    ./probe-mcp.ps1

.EXAMPLE
    ./probe-mcp.ps1 -Detailed

.EXAMPLE
    # For scripts: no banner, tool names on the pipeline, exit 1 if nothing answers.
    # This is how Ward General App's preflight-run.ps1 checks the endpoint before the app starts.
    $tools = ./probe-mcp.ps1 -Quiet
#>
[CmdletBinding()]
param(
    [int]    $Port = 5000,
    [string] $Url,
    [switch] $Detailed,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

if (-not $Url) { $Url = "http://localhost:$Port/mcp" }

# MCP over HTTP is a three-step handshake: initialize, acknowledge, then ask.
# Skipping the acknowledgement gets a session that answers nothing.
$accept = 'application/json, text/event-stream'
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1.0"}}}'

try {
    $r = Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' `
        -Body $init -Headers @{ Accept = $accept } -UseBasicParsing
}
catch {
    # A caller that is checking, rather than reading, wants a code it can branch on.
    if ($Quiet) { exit 1 }
    throw "No MCP endpoint answered at $Url. Start it with:  ./run-dab.ps1"
}

$sid = [string](@($r.Headers['Mcp-Session-Id'])[0])
$h = @{ Accept = $accept; 'Mcp-Session-Id' = $sid }

Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' `
    -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' -Headers $h -UseBasicParsing | Out-Null

$tl = Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' `
    -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' -Headers $h -UseBasicParsing

# The response may arrive as server-sent events, so strip the "data:" framing
# before parsing. A plain JSON body falls through unchanged.
$data = ($tl.Content -split "`n" | Where-Object { $_ -like 'data:*' } |
    ForEach-Object { $_.Substring(5).Trim() }) -join ''
if (-not $data) { $data = $tl.Content }

$tools = ($data | ConvertFrom-Json).result.tools

if ($Quiet) {
    $tools.name
    exit 0
}

Write-Host ''
Write-Host "$Url  —  $($tools.Count) tools" -ForegroundColor Cyan
foreach ($t in $tools) {
    $write = if ($t.name -eq 'save_handoff') { ' [WRITE - must be approval-gated in the app]' } else { '' }
    Write-Host "  - $($t.name)$write" -ForegroundColor $(if ($write) { 'Yellow' } else { 'White' })
    if ($Detailed -and $t.description) {
        Write-Host "      $($t.description)" -ForegroundColor DarkGray
    }
}
Write-Host ''
