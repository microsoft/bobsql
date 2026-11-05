<#
.SYNOPSIS
    Loads wardgeneral.env into the current process environment.

.DESCRIPTION
    Ward General App needs two values -- the server to talk to and the database on it.
    This is the one place they enter the configuration. Dot-source it to keep them for
    a whole session, or let run.ps1 and preflight-run.ps1 call it for you.

        . ./load-env.ps1          # values persist in this shell
        ./load-env.ps1            # values persist only for this script

    The file it reads is wardgeneral.env, which you create by copying
    wardgeneral.env.template. Run this with no arguments and it will do that copy for
    you and stop, because a template full of <placeholders> is not a
    configuration and running on with it produces a confusing failure later.

    OPTIONAL BY DESIGN. Ward General App has three ways to point the app at a database
    and this is only one of them, so run.ps1 and preflight-run.ps1 call this
    with -Optional: if wardgeneral.env does not exist they carry on quietly and let
    appsettings.Development.json or an explicit -Server take over. That is why a
    reader who never creates wardgeneral.env sees no change in behaviour at all.

    PRECEDENCE. A variable already set in the shell WINS over the file, and the
    file is not allowed to quietly overwrite it. Someone who exported
    WardGeneral__Server by hand meant it. Pass -Force to let the file win.

    Once loaded, these sit at the TOP of the app's own configuration chain --
    environment variables, then appsettings.Development.json, then
    appsettings.json -- so the app and the pre-flight both see the same values.

    This script sets environment variables and reads a text file. It creates
    nothing in Azure and contacts no network.

.PARAMETER Path
    The env file to read. Defaults to wardgeneral.env beside this script.

.PARAMETER Require
    Keys that must carry a real value. Anything still empty or still in <angle
    brackets> is reported and the script throws. Ignored under -Optional.

.PARAMETER Optional
    If the file does not exist, return quietly instead of creating it and
    throwing. Used by the scripts that call this automatically.

.PARAMETER Force
    Let the file overwrite variables already set in the shell.

.PARAMETER Quiet
    Suppress the per-variable output. Errors still print.

.EXAMPLE
    . ./load-env.ps1
    ./run.ps1

.EXAMPLE
    # Note the call operator. `pwsh -File load-env.ps1 -Require A,B` passes
    # "A,B" as a single string, so the check looks for one variable of that name
    # and reports it missing. Use & or dot-sourcing for array parameters.
    & ./load-env.ps1 -Require @('WardGeneral__Server')
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string]   $Path,
    [string[]] $Require = @('WardGeneral__Server', 'WardGeneral__Database'),
    [switch]   $Optional,
    [switch]   $Force,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = Join-Path $PSScriptRoot 'wardgeneral.env' }
$template = Join-Path $PSScriptRoot 'wardgeneral.env.template'

if (-not (Test-Path $Path)) {
    # The -Optional caller has other configuration sources and must not be
    # stopped just because this one is absent.
    if ($Optional) { return }

    if (Test-Path $template) {
        Copy-Item $template $Path
        Write-Host ''
        Write-Host "Created $Path from the template." -ForegroundColor Yellow
        Write-Host 'Open it, fill in your server name, then run this again.' -ForegroundColor Yellow
        Write-Host ''
    }
    throw "No wardgeneral.env yet. Fill in $Path and re-run."
}

# A value is "unfilled" if it is empty or still carries the <angle brackets> the
# template ships with.
#
# The match is deliberately "contains a placeholder", not "is a placeholder".
# WardGeneral__Server ships as <your-sql-server>.database.windows.net, so an
# anchored test would call that filled in and hand the app a hostname that
# cannot resolve.
function Test-Unfilled([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return $Value -match '<[^>]*>'
}

$loaded   = @{}
$skipped  = [System.Collections.Generic.List[string]]::new()
$lineNo   = 0

foreach ($line in (Get-Content -LiteralPath $Path)) {
    $lineNo++
    $trimmed = $line.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

    $split = $trimmed.IndexOf('=')
    if ($split -lt 1) {
        Write-Warning "${Path}:${lineNo}: not a KEY=VALUE line, ignored -- $trimmed"
        continue
    }

    $key   = $trimmed.Substring(0, $split).Trim()
    $value = $trimmed.Substring($split + 1).Trim()

    # Allow quoted values, but do not strip quotes that are part of the value.
    if ($value.Length -ge 2 -and
        (($value.StartsWith('"') -and $value.EndsWith('"')) -or
         ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    if (Test-Unfilled $value) { continue }

    $existing = [Environment]::GetEnvironmentVariable($key, 'Process')
    if (-not $Force -and -not [string]::IsNullOrWhiteSpace($existing) -and $existing -ne $value) {
        $skipped.Add("$key (shell has '$existing', file has '$value')")
        $loaded[$key] = $existing
        continue
    }

    Set-Item -Path "env:$key" -Value $value
    $loaded[$key] = $value
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host "Loaded $Path" -ForegroundColor Cyan
    foreach ($key in ($loaded.Keys | Sort-Object)) {
        Write-Host ("  {0,-24} {1}" -f $key, $loaded[$key]) -ForegroundColor DarkGray
    }
    foreach ($s in $skipped) {
        Write-Host "  kept the shell's value for $s" -ForegroundColor Yellow
    }
    Write-Host ''
}

# Under -Optional a half-filled file is not fatal here. The pre-flight reports
# "no server configured" with all three ways to fix it, which is the better
# message anyway -- this script only knows about one of the three.
if ($Optional) { return }

$missing = @($Require | Where-Object {
    [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_, 'Process'))
})

if ($missing.Count -gt 0) {
    Write-Host 'Still to fill in, in wardgeneral.env:' -ForegroundColor Red
    foreach ($m in $missing) { Write-Host "  $m" -ForegroundColor Red }
    Write-Host ''
    throw "wardgeneral.env is incomplete: $($missing -join ', ')."
}
