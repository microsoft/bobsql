$ErrorActionPreference = 'Stop'
$base = 'http://localhost:5000/mcp'
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1.0"}}}'
$h = @{ 'Accept' = 'application/json, text/event-stream' }
$r = Invoke-WebRequest -Uri $base -Method Post -ContentType 'application/json' -Body $init -Headers $h -UseBasicParsing
$data = ($r.Content -split "`n" | Where-Object { $_ -like 'data:*' } | ForEach-Object { $_.Substring(5).Trim() }) -join ''
if (-not $data) { $data = $r.Content }
$obj = $data | ConvertFrom-Json
Write-Host "serverInfo.name    : $($obj.result.serverInfo.name)"
Write-Host "serverInfo.version : $($obj.result.serverInfo.version)"
Write-Host "instructions       : $($obj.result.instructions)"
Write-Host "--- raw result ---"
$obj.result | ConvertTo-Json -Depth 6
