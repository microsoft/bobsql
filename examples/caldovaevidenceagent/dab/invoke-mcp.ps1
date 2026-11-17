[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Endpoint,
    [string]$AccessToken
)

$ErrorActionPreference = 'Stop'
$headers = @{
    Accept = 'application/json, text/event-stream'
    'Content-Type' = 'application/json'
}
if ($AccessToken) { $headers.Authorization = "Bearer $AccessToken" }

function Invoke-McpRequest {
    param([hashtable]$Payload, [string]$SessionId)

    $requestHeaders = $headers.Clone()
    if ($SessionId) { $requestHeaders['Mcp-Session-Id'] = $SessionId }
    $response = Invoke-WebRequest -Uri $Endpoint -Method Post -Headers $requestHeaders `
        -Body ($Payload | ConvertTo-Json -Depth 20 -Compress) -SkipHttpErrorCheck
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "MCP request failed with HTTP $($response.StatusCode): $($response.Content)"
    }
    $session = $response.Headers['Mcp-Session-Id'] | Select-Object -First 1
    $content = $response.Content
    if ($content -match '(?m)^data:\s*(\{.*\})\s*$') { $content = $Matches[1] }
    return [pscustomobject]@{ Body = ($content | ConvertFrom-Json); SessionId = $session }
}

$initialize = Invoke-McpRequest -Payload @{
    jsonrpc = '2.0'
    id = 1
    method = 'initialize'
    params = @{
        protocolVersion = '2025-03-26'
        capabilities = @{}
        clientInfo = @{ name = 'caldova-stage2-verifier'; version = '1.0' }
    }
}
$sessionId = $initialize.SessionId

$null = Invoke-McpRequest -SessionId $sessionId -Payload @{
    jsonrpc = '2.0'
    method = 'notifications/initialized'
}

$toolsResponse = Invoke-McpRequest -SessionId $sessionId -Payload @{
    jsonrpc = '2.0'
    id = 2
    method = 'tools/list'
    params = @{}
}
$tools = @($toolsResponse.Body.result.tools)
$expectedTools = @('get_article_context', 'get_corpus_status', 'search_evidence')
$actualTools = @($tools.name | Sort-Object)
if (($actualTools -join ',') -ne ($expectedTools -join ',')) {
    throw "Expected exactly $($expectedTools -join ', '); received $($actualTools -join ', ')."
}

$statusResponse = Invoke-McpRequest -SessionId $sessionId -Payload @{
    jsonrpc = '2.0'
    id = 3
    method = 'tools/call'
    params = @{ name = 'get_corpus_status'; arguments = @{} }
}
$statusIsError = $statusResponse.Body.result.PSObject.Properties['isError'] -and $statusResponse.Body.result.isError
if ($statusIsError) { throw 'get_corpus_status returned an MCP tool error.' }

$searchResponse = Invoke-McpRequest -SessionId $sessionId -Payload @{
    jsonrpc = '2.0'
    id = 4
    method = 'tools/call'
    params = @{
        name = 'search_evidence'
        arguments = @{
            question = 'How does disruption of the intestinal microbiome influence anxiety and depressive symptoms?'
            top_k = 3
        }
    }
}
$searchIsError = $searchResponse.Body.result.PSObject.Properties['isError'] -and $searchResponse.Body.result.isError
if ($searchIsError) {
    throw "search_evidence returned an MCP tool error: $($searchResponse.Body.result | ConvertTo-Json -Depth 20 -Compress)"
}

Write-Host 'MCP contract verified' -ForegroundColor Green
Write-Host "  Endpoint: $Endpoint"
Write-Host "  Tools:    $($actualTools -join ', ')"
Write-Host '  get_corpus_status: passed'
Write-Host '  search_evidence: passed'
