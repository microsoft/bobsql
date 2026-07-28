$ErrorActionPreference = 'Stop'
$base = 'http://localhost:5000/mcp'
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1.0"}}}'
$h = @{ 'Accept' = 'application/json, text/event-stream' }
$r = Invoke-WebRequest -Uri $base -Method Post -ContentType 'application/json' -Body $init -Headers $h -UseBasicParsing
$sid = [string](@($r.Headers['Mcp-Session-Id'])[0])
Write-Host "session: $sid"
$h2 = @{ 'Accept' = 'application/json, text/event-stream'; 'Mcp-Session-Id' = $sid }
Invoke-WebRequest -Uri $base -Method Post -ContentType 'application/json' -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' -Headers $h2 -UseBasicParsing | Out-Null
$tl = Invoke-WebRequest -Uri $base -Method Post -ContentType 'application/json' -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' -Headers $h2 -UseBasicParsing
$data = ($tl.Content -split "`n" | Where-Object { $_ -like 'data:*' } | ForEach-Object { $_.Substring(5).Trim() }) -join ''
if (-not $data) { $data = $tl.Content }
$tools = ($data | ConvertFrom-Json).result.tools
Write-Host "tool count: $($tools.Count)"
$tools | ForEach-Object { Write-Host ("  - " + $_.name) }
