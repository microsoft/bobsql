[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
. "$PSScriptRoot\00-config.ps1"

Write-Host 'Caldova Evidence Agent: complete build' -ForegroundColor Cyan
$python = Get-Command python -ErrorAction Stop
if (-not (Test-Path (Join-Path $root '.venv'))) {
    & $python.Source -m venv (Join-Path $root '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Python virtual environment creation failed.' }
}
$venvPython = Join-Path $root '.venv\Scripts\python.exe'
& $venvPython -m pip install -r (Join-Path $root 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Python dependency installation failed.' }

Push-Location (Join-Path $root 'app')
try {
    & npm ci
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Application build failed.' }
} finally { Pop-Location }

Push-Location (Join-Path $root 'agent\hosted\caldova-evidence-hosted')
try {
    & dotnet build '.\src\foundry-toolbox-mcp-skills\foundry-toolbox-mcp-skills.csproj' --configuration Release
    if ($LASTEXITCODE -ne 0) { throw 'Hosted agent build failed.' }
} finally { Pop-Location }

foreach ($stage in @(
    '01-preflight.ps1',
    '02-deploy-sql-infrastructure.ps1',
    '03-initialize-sql.ps1',
    '04-verify-sql.ps1',
    '05-deploy-dab-container-app.ps1',
    '06-verify-dab-container-app.ps1',
    '07-deploy-foundry-infrastructure.ps1',
    '08-deploy-hosted-agent.ps1',
    '09-deploy-app-service.ps1',
    '11-verify-system.ps1'
)) {
    & (Join-Path $PSScriptRoot $stage)
    if ($LASTEXITCODE -ne 0) { throw "$stage failed." }
    if ($stage -eq '08-deploy-hosted-agent.ps1') {
        & (Join-Path $PSScriptRoot '10-verify-hosted-agent.ps1') -EnvironmentName $AzdEnvironmentName -HostedAgentName $HostedAgentName
        if ($LASTEXITCODE -ne 0) { throw '10-verify-hosted-agent.ps1 failed.' }
    }
}

Write-Host "`nComplete Caldova Evidence Agent build passed." -ForegroundColor Green
