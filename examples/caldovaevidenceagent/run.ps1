[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = $PSScriptRoot
. "$root\deploy\00-config.ps1"
$agentRoot = Join-Path $root 'agent\hosted\caldova-evidence-hosted'
$appRoot = Join-Path $root 'app'
$runRoot = Join-Path $root '.run'
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$pidPath = Join-Path $runRoot 'app.pid'

$agentEndpoint = $env:CALDOVA_AGENT_ENDPOINT
$agentVersion = $env:CALDOVA_AGENT_VERSION
if (-not $agentEndpoint -or -not $agentVersion) {
    Push-Location $agentRoot
    try {
        $env:AZURE_DEV_USER_AGENT = 'caldova_evidence_agent_publish'
        $agentOutput = & azd ai agent show $HostedAgentName --environment $AzdEnvironmentName --output json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $agent = ($agentOutput | Out-String) | ConvertFrom-Json
            if ($agent.status -eq 'active') {
                $agentVersion = [string]$agent.version
                $agentEndpoint = "$FoundryProjectEndpoint/agents/$HostedAgentName/endpoint/protocols/openai/responses?api-version=v1"
            }
        }
    } finally { Pop-Location }
}

if (-not $agentEndpoint -or -not $agentVersion) {
    $configuredName = $AppServiceName
    $deployedNames = & az webapp list --subscription $ExpectedSubscriptionId `
        --resource-group $ResourceGroup --query '[].name' --output tsv 2>$null
    $candidateNames = @($configuredName) + @($deployedNames -split "`r?`n") |
        Where-Object { $_ } | Select-Object -Unique

    foreach ($appName in $candidateNames) {
        $settingsOutput = & az webapp config appsettings list --subscription $ExpectedSubscriptionId `
            --resource-group $ResourceGroup --name $appName `
            --query "[?name=='CALDOVA_AGENT_ENDPOINT' || name=='CALDOVA_AGENT_VERSION'].{name:name,value:value}" `
            --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $settingsOutput) { continue }

        $settings = ($settingsOutput | Out-String) | ConvertFrom-Json
        $deployedEndpoint = ($settings | Where-Object name -eq 'CALDOVA_AGENT_ENDPOINT').value
        $deployedVersion = ($settings | Where-Object name -eq 'CALDOVA_AGENT_VERSION').value
        if ($deployedEndpoint -and $deployedVersion) {
            $agentEndpoint = [string]$deployedEndpoint
            $agentVersion = [string]$deployedVersion
            break
        }
    }
}

if (-not $agentEndpoint -or -not $agentVersion) {
    throw "Could not resolve the hosted agent from explicit environment variables, azd environment '$AzdEnvironmentName', or App Service settings in resource group '$ResourceGroup'. Deploy first or set CALDOVA_AGENT_ENDPOINT and CALDOVA_AGENT_VERSION."
}

$env:CALDOVA_AGENT_ENDPOINT = $agentEndpoint
$env:CALDOVA_AGENT_NAME = if ($env:CALDOVA_AGENT_NAME) { $env:CALDOVA_AGENT_NAME } else { $HostedAgentName }
$env:CALDOVA_AGENT_VERSION = $agentVersion
$env:HOST = '127.0.0.1'
$env:PORT = '8000'

if (-not (Test-Path (Join-Path $appRoot 'node_modules'))) {
    & npm ci --prefix $appRoot
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
}
& npm run build --prefix $appRoot
if ($LASTEXITCODE -ne 0) { throw 'Application build failed.' }

$reuse = $false
if (Test-Path $pidPath) {
    $existingPid = [int](Get-Content -Raw $pidPath)
    $reuse = [bool](Get-Process -Id $existingPid -ErrorAction SilentlyContinue)
}
if (-not $reuse) {
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    $tsx = Join-Path $appRoot 'node_modules\tsx\dist\cli.mjs'
    $server = Join-Path $appRoot 'server\index.ts'
    $process = Start-Process -FilePath $node -ArgumentList @($tsx, $server) `
        -WorkingDirectory $appRoot -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $runRoot 'app.out.log') `
        -RedirectStandardError (Join-Path $runRoot 'app.err.log') -PassThru
    Set-Content -Path $pidPath -Value $process.Id -Encoding ascii
}

$ready = $false
foreach ($attempt in 1..30) {
    try {
        $response = Invoke-RestMethod 'http://127.0.0.1:8000/api/agent/readiness' -TimeoutSec 3
        if ($response.configured) { $ready = $true; break }
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $ready) { throw "Local application did not become ready. See $runRoot\app.err.log." }

$edgeCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
)
$edge = $edgeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Microsoft Edge was not found.' }
Start-Process -FilePath $edge -ArgumentList '--app=http://127.0.0.1:8000/'
$edgeReady = $false
foreach ($attempt in 1..20) {
    $edgeReady = [bool](Get-Process msedge -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like '*Caldova*' } |
        Select-Object -First 1)
    if ($edgeReady) { break }
    Start-Sleep -Milliseconds 250
}
if (-not $edgeReady) { throw 'Microsoft Edge started, but the standalone Caldova window was not detected.' }
Write-Host "Caldova Evidence Agent is running at http://127.0.0.1:8000/ (hosted agent v$agentVersion)." -ForegroundColor Green
