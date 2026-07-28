#requires -Version 7.0
<#
    Ward General — tear down the LOCAL demo footprint on this machine.

    Does (local only):
      1. shutdown.ps1  — stop the app + DAB.
      2. Remove .NET build artifacts (bin/ obj/ under src/, and any publish/).
      3. (opt-in) -RemoveDabTool  — uninstall the global DAB CLI.

    Does NOT touch Azure or the database. The `wardgeneral` Hyperscale database
    is provisioned separately (deploy-wardgeneral-db skill) and is SHARED with
    the book — a demo teardown must never drop it. To remove the Azure resources
    you must do it deliberately and by hand (e.g. `az group delete -n rg-collierhealth`),
    knowing it also destroys the book's database.

    Usage:
      ./teardown.ps1                 # stop + clean build artifacts
      ./teardown.ps1 -RemoveDabTool  # also uninstall the global DAB CLI
      ./teardown.ps1 -KeepArtifacts  # stop only, leave bin/obj in place
#>
[CmdletBinding()]
param(
    [switch]$RemoveDabTool,
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# 1. Stop everything.
& (Join-Path $root 'shutdown.ps1')

# 2. Remove build artifacts.
if (-not $KeepArtifacts) {
    Write-Host "Removing build artifacts (bin/ obj/ publish/) ..." -ForegroundColor Cyan
    $targets = Get-ChildItem -Path (Join-Path $root 'src') -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('bin', 'obj') }
    $targets += Get-ChildItem -Path (Join-Path $root 'src') -Recurse -Directory -Filter 'publish' -ErrorAction SilentlyContinue
    foreach ($t in $targets) {
        Remove-Item -LiteralPath $t.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  removed $($targets.Count) folder(s)." -ForegroundColor DarkGray
}

# 3. Optionally uninstall the DAB global tool.
if ($RemoveDabTool) {
    if (Get-Command dab -ErrorAction SilentlyContinue) {
        Write-Host "Uninstalling the DAB CLI (Microsoft.DataApiBuilder) ..." -ForegroundColor Cyan
        dotnet tool uninstall --global Microsoft.DataApiBuilder
    }
    else {
        Write-Host "DAB CLI not installed; nothing to uninstall." -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Local teardown complete. Azure / the wardgeneral database were NOT touched." -ForegroundColor Green
Write-Host "Rebuild with ./build.ps1, run with ./run.ps1." -ForegroundColor DarkGray
