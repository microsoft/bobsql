#requires -Version 7.0
<#
    Rehearsal helper — call one MCP tool on the Adventure Works SQL MCP Server (HTTP :5001)
    and print the JSON result. Used to PROVE a demo beat works before running it in
    agent-mode chat. Drives the SAME server VS Code is registered against, so there is no
    "agent misrouted to Ward General" ambiguity.

    Usage:
      ./mcp-call.ps1 describe_entities
      ./mcp-call.ps1 read_records -Arguments @{ entity='ProductComponents'; filter="ProductModel eq 'Touring-1000'" }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Tool,
    [hashtable]$Arguments = @{},
    [string]$Url = 'http://localhost:5001/mcp'
)
$ErrorActionPreference = 'Stop'
$headers = @{ Accept = 'application/json, text/event-stream' }

function Send-Mcp($obj) {
    Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' `
        -Headers $headers -Body ($obj | ConvertTo-Json -Depth 20) -UseBasicParsing
}
function Get-SseJson($resp) {
    $line = ($resp.Content -split "`n" | Where-Object { $_ -like 'data: *' } | Select-Object -Last 1)
    ($line -replace '^data:\s*', '') | ConvertFrom-Json
}

# 1) initialize (capture session id if the server issues one)
$init = Send-Mcp @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{
        protocolVersion = '2025-06-18'; capabilities = @{}; clientInfo = @{ name = 'rehearsal'; version = '1.0' } } }
$sid = $init.Headers['Mcp-Session-Id']
if ($sid) { $headers['Mcp-Session-Id'] = "$sid" }

# 2) initialized notification
Send-Mcp @{ jsonrpc = '2.0'; method = 'notifications/initialized' } | Out-Null

# 3) tools/call
$resp = Send-Mcp @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } }
$parsed = Get-SseJson $resp
if ($parsed.error) { throw "MCP error: $($parsed.error | ConvertTo-Json -Depth 8)" }

# DAB returns tool output as content[].text (usually JSON) — print each block.
foreach ($c in $parsed.result.content) { $c.text }
