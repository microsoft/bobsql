<#
.SYNOPSIS
    Probe the secured DAB MCP endpoint with a simulated acting-provider claim.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Nullable[int]] $ProviderId,
    [ValidateSet('Admin', 'Attending')]
    [string] $Role = 'Admin',
    [int] $Port = 5000,
    [string] $Url,
    [ValidateRange(0, 300)]
    [int] $StartupTimeoutSeconds = 60,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'new-client-principal.ps1')

if ($Role -eq 'Attending' -and $null -eq $ProviderId) {
    throw 'Attending probes require -ProviderId.'
}

$headers = @{
    Accept = 'application/json, text/event-stream'
    'X-MS-CLIENT-PRINCIPAL' = New-ClientPrincipalHeader -ProviderId $ProviderId -Role $Role
}
if (-not $Url) { $Url = "http://localhost:$Port/mcp" }
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"security-rls-probe","version":"1.0"}}}'

$deadline = [DateTimeOffset]::UtcNow.AddSeconds($StartupTimeoutSeconds)
while ($true) {
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' `
            -Body $init -Headers $headers -UseBasicParsing
        break
    }
    catch {
        if ($null -ne $_.Exception.Response) { throw }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "DAB did not become ready at $Url within $StartupTimeoutSeconds seconds."
        }
        Start-Sleep -Seconds 1
    }
}
$sessionId = [string] (@($response.Headers['Mcp-Session-Id'])[0])
if ([string]::IsNullOrWhiteSpace($sessionId)) { throw 'DAB returned no MCP session ID.' }
$headers['Mcp-Session-Id'] = $sessionId

Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' `
    -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' `
    -Headers $headers -UseBasicParsing | Out-Null
$toolResponse = Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' `
    -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' `
    -Headers $headers -UseBasicParsing
$data = ($toolResponse.Content -split "`n" | Where-Object { $_ -like 'data:*' } |
    ForEach-Object { $_.Substring(5).Trim() }) -join ''
if (-not $data) { $data = $toolResponse.Content }
$tools = ($data | ConvertFrom-Json).result.tools

if ($Quiet) {
    $tools.name
    return
}

Write-Host "$Url — $($tools.Count) authenticated tools" -ForegroundColor Cyan
Write-Host "Acting context: $Role$(if ($null -ne $ProviderId) { " / provider $ProviderId" })" -ForegroundColor Gray
$tools.name | Sort-Object | ForEach-Object { Write-Host "  - $_" }
