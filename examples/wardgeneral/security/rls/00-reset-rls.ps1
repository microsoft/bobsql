<#
.SYNOPSIS
    Return the Ward General lab to its pre-Security RLS state.

.DESCRIPTION
    Stops only recognized Ward General and DAB processes, drops only the
    Security RLS policy and predicate, removes obsolete adapter procedures
    from earlier revisions, removes the generated local DAB configuration,
    and verifies that no Security RLS objects remain. Ward General App–6 objects and
    application source are preserved.
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd,
    [int] $DabPort = 5000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

& (Join-Path $here 'stop-local-apps.ps1') -DabPort $DabPort `
    -WhatIf:$WhatIfPreference

$loadEnv = Join-Path $here '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) {
    $resetWhatIfPreference = $WhatIfPreference
    try {
        $WhatIfPreference = $false
        & $loadEnv -Optional -Quiet
    }
    finally {
        $WhatIfPreference = $resetWhatIfPreference
    }
}
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}

$isGoSqlcmd = {
    param([string] $Executable)
    if (-not $Executable) { return $false }
    & $Executable --version 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}
$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) -and (& $isGoSqlcmd $_) } |
    Select-Object -First 1
if (-not $sqlcmdPath) { throw 'The new Go-based sqlcmd was not found.' }

if ($PSCmdlet.ShouldProcess(
    "$Database on $Server",
    'Drop only the Security RLS policy, predicate, and obsolete adapter procedures'
)) {
    & $sqlcmdPath -S $Server -d $Database -G -C -b `
        -i (Join-Path $here '00-reset-rls.sql')
    if ($LASTEXITCODE -ne 0) { throw "RLS reset failed (sqlcmd exit $LASTEXITCODE)." }
}

$local = Join-Path $here '_local'
if ((Test-Path $local) -and $PSCmdlet.ShouldProcess(
    $local,
    'Remove generated Security DAB configuration and logs'
)) {
    Remove-Item -LiteralPath $local -Recurse -Force
}

if ($WhatIfPreference) {
    Write-Host 'WhatIf complete. Nothing was stopped, dropped, or removed.' -ForegroundColor Green
    return
}

$result = @(& $sqlcmdPath -S $Server -d $Database -G -C -b -h -1 -W `
    -i (Join-Path $here '00-verify-clean.sql'))
if ($LASTEXITCODE -ne 0) { throw "Clean-state verification failed (sqlcmd exit $LASTEXITCODE)." }
$remaining = [int] ([string] ($result | Where-Object { $_ -match '^\s*\d+\s*$' } |
    Select-Object -Last 1)).Trim()
if ($remaining -ne 0) {
    throw "Security reset is incomplete: $remaining RLS object(s) remain."
}

Write-Host 'Security RLS reset complete.' -ForegroundColor Green
Write-Host 'Ward General is stopped, DAB is stopped, generated files are removed,'
Write-Host 'and all Ward General App–6 objects remain in place.'
