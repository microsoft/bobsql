#requires -Version 7.4
[CmdletBinding()]
param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$url = 'http://localhost:5188'
$publish = Join-Path $PSScriptRoot 'server\bin\publish'
$dll = Join-Path $publish 'MigrationStudio.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Run build.ps1 before starting Migration Studio.' }
$listeners = @(Get-NetTCPConnection -LocalPort 5188 -State Listen -ErrorAction SilentlyContinue)
if ($listeners.Count -eq 0) {
    $process = Start-Process -FilePath (Get-Command dotnet -ErrorAction Stop).Source `
        -ArgumentList @("`"$dll`"", '--contentRoot', "`"$(Join-Path $PSScriptRoot 'server')`"") `
        -WorkingDirectory $publish -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $publish 'studio.stdout.log') `
        -RedirectStandardError (Join-Path $publish 'studio.stderr.log')
    Write-Host "Started SQL Migration Studio process $($process.Id)."
} else {
    foreach ($processId in @($listeners.OwningProcess | Select-Object -Unique)) {
        $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$processId"
        if ($existing.CommandLine -notlike "*$dll*") {
            throw "Port 5188 belongs to another process ($processId). No process was stopped."
        }
    }
    Write-Host 'Reusing the published SQL Migration Studio.'
}
$healthJson = & curl.exe --fail --silent --show-error --retry 20 --retry-connrefused `
    --retry-delay 1 --retry-max-time 40 --max-time 10 "$url/health"
if ($LASTEXITCODE -ne 0) { throw 'Migration Studio did not become reachable within the startup window.' }
$health = $healthJson | ConvertFrom-Json
if ($health.app -ne 'sql-migration-studio' -or $health.status -ne 'ready') {
    throw 'Migration Studio host readiness failed.'
}
$page = Invoke-WebRequest $url -TimeoutSec 15
if ($page.StatusCode -ne 200 -or $page.Content -notmatch 'id="root"') {
    throw 'The frontend was not built or could not be served.'
}
Write-Host "Ready: $url. No cloud migration has been started."
if (-not $NoBrowser) {
    $edge = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edge) { throw 'Studio is running, but Microsoft Edge could not be found.' }
    Start-Process -FilePath $edge -ArgumentList "--app=$url"
    Write-Host 'Opened standalone Microsoft Edge app window.'
}
