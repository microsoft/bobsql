$ErrorActionPreference = 'Stop'
$base = 'http://localhost:5000/mcp'
$h = @{ 'Accept' = 'application/json, text/event-stream' }
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1.0"}}}'
$r = Invoke-WebRequest -Uri $base -Method Post -ContentType 'application/json' -Body $init -Headers $h -UseBasicParsing
$sid = [string](@($r.Headers['Mcp-Session-Id'])[0])
$h2 = @{ 'Accept' = 'application/json, text/event-stream'; 'Mcp-Session-Id' = $sid }
Invoke-WebRequest -Uri $base -Method Post -ContentType 'application/json' -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' -Headers $h2 -UseBasicParsing | Out-Null

# tools/call — this is the ACTUAL MCP protocol invocation (not REST)
$call = @{
    jsonrpc = '2.0'; id = 3; method = 'tools/call'
    params  = @{
        name      = 'search_similar_notes'
        arguments = @{ QueryText = 'elderly chest pain with elevated troponin'; TopK = 5 }
    }
} | ConvertTo-Json -Depth 6

Write-Host "--> MCP tools/call: search_similar_notes" -ForegroundColor Cyan
$resp = Invoke-WebRequest -Uri $base -Method Post -ContentType 'application/json' -Body $call -Headers $h2 -UseBasicParsing
$data = ($resp.Content -split "`n" | Where-Object { $_ -like 'data:*' } | ForEach-Object { $_.Substring(5).Trim() }) -join ''
if (-not $data) { $data = $resp.Content }
$obj = $data | ConvertFrom-Json
Write-Host "isError: $($obj.result.isError)"
# DAB returns the rows as text content inside the tool result
$obj.result.content | ForEach-Object { $_.text } | Write-Host
