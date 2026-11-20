#requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot 'client')
try {
    if (-not (Test-Path -LiteralPath 'node_modules')) {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw 'Frontend dependency restore failed.' }
    }
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Frontend type-check or build failed.' }
} finally { Pop-Location }
$project = Join-Path $PSScriptRoot 'server\MigrationStudio.csproj'
& dotnet publish $project --configuration Release --output (Join-Path $PSScriptRoot 'server\bin\publish')
if ($LASTEXITCODE -ne 0) { throw 'Migration Studio publish failed.' }
Write-Host 'Published SQL Migration Studio. No Azure resource or source database was changed.'
