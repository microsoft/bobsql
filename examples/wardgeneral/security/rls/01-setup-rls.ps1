<#
.SYNOPSIS
    Prepare the already-built Ward General application for the Security RLS example.

.DESCRIPTION
    Stops recognized Ward General and DAB processes when present, deploys the
    Security RLS policy, rebuilds the cumulative application, and generates
    and validates the secured DAB configuration. This script finishes; it does
    not start either long-running process.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [int] $DabPort = 5000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$area4 = Join-Path $here '..' '..' 'first-app'

& (Join-Path $here 'stop-local-apps.ps1') -DabPort $DabPort
& (Join-Path $here 'enable-rls.ps1') -Server $Server -Database $Database
& (Join-Path $area4 'build.ps1')

$generatedConfig = @(& (Join-Path $here '02-run-secured-dab.ps1') `
    -Server $Server -Database $Database -Port $DabPort -PrepareOnly) |
    Select-Object -Last 1
if (-not (Test-Path $generatedConfig)) {
    throw "Secured DAB config was not generated: $generatedConfig"
}

Write-Host ''
Write-Host 'Security RLS setup is complete.' -ForegroundColor Green
Write-Host 'Open two visible terminals and run:' -ForegroundColor Cyan
Write-Host '  Terminal 1: ./security/rls/02-run-secured-dab.ps1'
Write-Host '  Terminal 2: ./security/rls/03-run-rls-app.ps1'
