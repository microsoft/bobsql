#requires -Version 7.0
<#
.SYNOPSIS
Builds and publishes the Service Desk app without changing database data.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
dotnet publish (Join-Path $PSScriptRoot 'app\CustomerServiceDesk.csproj') `
    --configuration Release --output (Join-Path $PSScriptRoot 'app\bin\publish')
if ($LASTEXITCODE -ne 0) { throw 'Application publish failed.' }
Write-Host 'Published app\bin\publish. Run run-app.ps1 to start this exact artifact.'
