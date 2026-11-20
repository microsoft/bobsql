#requires -Version 7.0
# Pull the public Azure SQL Database development image.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Image = 'mcr.microsoft.com/mssql/azure-sql-db-server:latest',
    [switch]$StartDockerDesktop
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repository = 'mcr.microsoft.com/mssql/azure-sql-db-server'
if (-not $Image.StartsWith("${repository}:", [StringComparison]::Ordinal) -and
    -not $Image.StartsWith("${repository}@", [StringComparison]::Ordinal)) {
    throw "Image must be a tag or digest in '$repository'."
}

& (Join-Path $PSScriptRoot 'preflight.ps1') -DockerOnly -StartDockerDesktop:$StartDockerDesktop

docker pull $Image | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Docker pull failed for '$Image' (exit code $LASTEXITCODE). Check the Docker output above."
}
