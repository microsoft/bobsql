<#
.SYNOPSIS
    Call one secured DAB MCP tool under a simulated provider identity.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int] $ProviderId,
    [int] $EncounterId = 200375,
    [int] $Port = 5000
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'new-client-principal.ps1')

$url = "http://localhost:$Port/mcp"
$headers = @{
    Accept = 'application/json, text/event-stream'
    'X-MS-CLIENT-PRINCIPAL' = New-ClientPrincipalHeader `
        -ProviderId $ProviderId -Role Attending
}
$initialize = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"security-rls-tool-test","version":"1.0"}}}'
$response = Invoke-WebRequest -Uri $url -Method Post -ContentType 'application/json' `
    -Body $initialize -Headers $headers -UseBasicParsing
$sessionId = [string] (@($response.Headers['Mcp-Session-Id'])[0])
$headers['Mcp-Session-Id'] = $sessionId

Invoke-WebRequest -Uri $url -Method Post -ContentType 'application/json' `
    -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' `
    -Headers $headers -UseBasicParsing | Out-Null

$call = @{
    jsonrpc = '2.0'
    id = 2
    method = 'tools/call'
    params = @{
        name = 'get_patient_chart'
        arguments = @{ EncounterId = $EncounterId }
    }
} | ConvertTo-Json -Depth 6
$toolResponse = Invoke-WebRequest -Uri $url -Method Post -ContentType 'application/json' `
    -Body $call -Headers $headers -UseBasicParsing
$data = ($toolResponse.Content -split "`n" | Where-Object { $_ -like 'data:*' } |
    ForEach-Object { $_.Substring(5).Trim() }) -join ''
if (-not $data) { $data = $toolResponse.Content }
$result = ($data | ConvertFrom-Json).result

[pscustomobject]@{
    ProviderId = $ProviderId
    EncounterId = $EncounterId
    IsError = [bool] $result.isError
    Content = ($result.content.text -join "`n")
}
