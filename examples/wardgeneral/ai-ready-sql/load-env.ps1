<#
.SYNOPSIS
    Loads ai.env into the current process environment.

.DESCRIPTION
    Every script in this folder reads its values from environment variables, so
    this is the one place the reader's resource names enter the configuration. Dot-
    source it to keep the values for a whole session, or let another script call
    it.

        . ./load-env.ps1          # values persist in this shell
        ./load-env.ps1            # values persist only for this script

    The file it reads is ai.env, which the reader creates by copying
    ai.env.template. If ai.env is missing this script copies the template
    into place and stops, because a template full of <placeholders> is not a
    configuration and running on with it would produce a confusing failure three
    steps later.

    PRECEDENCE. A variable already set in the shell WINS over the file, and the
    file is not allowed to quietly overwrite it. Someone who exported SRV by
    hand meant it. Pass -Force to let the file win instead.

    This script sets environment variables and reads a text file. It creates
    nothing in Azure and contacts no network.

.PARAMETER Path
    The env file to read. Defaults to ai.env beside this script.

.PARAMETER Require
    Keys that must carry a real value. Anything still empty or still in <angle
    brackets> is reported and the script throws.

.PARAMETER Force
    Let the file overwrite variables already set in the shell.

.PARAMETER Quiet
    Suppress the per-variable output. Errors still print.

.EXAMPLE
    . ./load-env.ps1
    ./deploy-ai.ps1

.EXAMPLE
    # Note the call operator. `pwsh -File load-env.ps1 -Require RG,SRV` passes
    # "RG,SRV" as a single string, so the check looks for one variable of that
    # name and reports it missing. Use & or dot-sourcing for array parameters.
    & ./load-env.ps1 -Require @('RG', 'SRV', 'AI_RESOURCE')
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string]   $Path,
    [string[]] $Require = @('RG', 'SRV', 'AI_RESOURCE'),
    [switch]   $Force,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = Join-Path $PSScriptRoot 'ai.env' }
$template = Join-Path $PSScriptRoot 'ai.env.template'

if (-not (Test-Path $Path)) {
    if (Test-Path $template) {
        Copy-Item $template $Path
        Write-Host ''
        Write-Host "Created $Path from the template." -ForegroundColor Yellow
        Write-Host 'Open it, fill in your resource names, then run this again.' -ForegroundColor Yellow
        Write-Host ''
    }
    throw "No ai.env yet. Fill in $Path and re-run."
}

# A value is "unfilled" if it is empty or still carries the <angle brackets> the
# template ships with. Same convention as the SQL scripts' <your-foundry>, so a
# reader learns one rule for the whole area.
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
$unfilled = [System.Collections.Generic.List[string]]::new()
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

    if (Test-Unfilled $value) { $unfilled.Add($key); continue }

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

$missing = @($Require | Where-Object {
    [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_, 'Process'))
})

if ($missing.Count -gt 0) {
    Write-Host 'Still to fill in, in ai.env:' -ForegroundColor Red
    foreach ($m in $missing) { Write-Host "  $m" -ForegroundColor Red }
    Write-Host ''
    throw "ai.env is incomplete: $($missing -join ', ')."
}
