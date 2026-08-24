# Serve web\index.html on http://localhost:8080 so the SignalR client has a real
# origin. A file:// page sends Origin: null, which CORS cannot allow-list.

. "$PSScriptRoot\00-config.ps1"

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$WebPort/")

try {
    $listener.Start()
}
catch {
    throw "Could not listen on port $WebPort. Is something already using it?`n$($_.Exception.Message)"
}

$pageUrl = "$WebOrigin/index.html?api=https://$FunctionApp.azurewebsites.net"

Write-Step "Serving $WebDir"
Write-Ok $pageUrl
Write-Skip 'Ctrl+C to stop'

# Force a real, standalone browser window. Start-Process on the bare URL hands it
# to whatever is registered for http, which can be an embedded viewer.
$browsers = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
)
$browser = $browsers | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($browser) {
    Start-Process $browser -ArgumentList '--new-window', $pageUrl
}
else {
    Start-Process $pageUrl
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path = $context.Request.Url.LocalPath.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($path)) { $path = 'index.html' }

        $file = Join-Path $WebDir $path
        # Keep the listener inside web\ even if the URL tries to climb out.
        $full = [System.IO.Path]::GetFullPath($file)
        if (-not $full.StartsWith([System.IO.Path]::GetFullPath($WebDir), [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
            $context.Response.StatusCode = 404
            $context.Response.Close()
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($full)
        $context.Response.ContentType = switch ([System.IO.Path]::GetExtension($full)) {
            '.html' { 'text/html; charset=utf-8' }
            '.js' { 'application/javascript' }
            '.css' { 'text/css' }
            default { 'application/octet-stream' }
        }
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
