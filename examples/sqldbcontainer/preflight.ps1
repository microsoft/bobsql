#requires -Version 7.0
<#
.SYNOPSIS
Checks Docker and a working local Ollama embedding model.
.DESCRIPTION
Does not install software, switch Docker contexts, download models or images,
accept licenses, or create containers. Warms the selected embedding model.
Use -DockerOnly for container setup that does not require embeddings.
#>
[CmdletBinding()]
param(
    [switch]$StartDockerDesktop,
    [switch]$DockerOnly,
    [ValidateNotNullOrEmpty()]
    [string]$EmbeddingModel = 'nomic-embed-text:v1.5',
    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    $docker = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'
    if (-not (Test-Path -LiteralPath $docker)) {
        throw 'Docker CLI not found. Install Docker Desktop, select Linux containers, and rerun in PowerShell 7.'
    }
    $env:PATH = "$(Split-Path $docker);$env:PATH"
}

$infoFormat = '{"OSType":{{json .OSType}},"Architecture":{{json .Architecture}},"ServerVersion":{{json .ServerVersion}},"NCPU":{{json .NCPU}},"MemTotal":{{json .MemTotal}}}'
$info = docker info --format $infoFormat 2>&1
$dockerExitCode = $LASTEXITCODE
if ($dockerExitCode -ne 0) {
    Write-Host ($info -join [Environment]::NewLine)
    if (-not $StartDockerDesktop) {
        throw 'Docker engine is unreachable. Start Docker Desktop or rerun with -StartDockerDesktop. No container changes were made.'
    }

    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $desktop)) {
        throw 'Docker Desktop.exe was not found. Start your Docker engine manually and rerun.'
    }
    Write-Host 'Starting Docker Desktop; waiting for the engine...'
    Start-Process -FilePath $desktop | Out-Null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds 2
        $info = docker info --format $infoFormat 2>&1
        $dockerExitCode = $LASTEXITCODE
    } while ($dockerExitCode -ne 0 -and $timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)

    if ($dockerExitCode -ne 0) {
        Write-Host ($info -join [Environment]::NewLine)
        throw "Docker engine did not become available within $TimeoutSeconds seconds."
    }
}

$engine = ($info -join [Environment]::NewLine) | ConvertFrom-Json
if ($engine.OSType -ne 'linux') {
    throw "Docker is using '$($engine.OSType)' containers. Select Linux containers in Docker Desktop and rerun."
}
if ($engine.Architecture -notin @('x86_64', 'amd64')) {
    throw "This setup targets Linux x64; Docker reports '$($engine.Architecture)'. No emulation is configured."
}

$context = docker context show
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to determine the active Docker context.'
}
Write-Host "Docker pre-flight passed. Context: $context; engine: $($engine.ServerVersion); Linux $($engine.Architecture)."
Write-Host ('Engine resources: {0} CPUs, {1:N1} GiB memory.' -f $engine.NCPU, ($engine.MemTotal / 1GB))
if ($DockerOnly) {
    Write-Host 'Docker-only setup check: Ollama and embeddings were not checked.'
    return
}

$ollama = 'http://localhost:11434'
try {
    $models = Invoke-RestMethod -Uri "$ollama/api/tags" -TimeoutSec $TimeoutSeconds
} catch {
    throw "Ollama is unreachable at $ollama. Start Ollama and rerun preflight. $($_.Exception.Message)"
}
$model = @($models.models | Where-Object { $_.name -eq $EmbeddingModel })
if ($model.Count -ne 1) {
    throw "Ollama embedding model '$EmbeddingModel' is not installed. Run: ollama pull $EmbeddingModel"
}

try {
    $metadata = Invoke-RestMethod -Uri "$ollama/api/show" -Method Post -ContentType 'application/json' `
        -Body (@{ model = $EmbeddingModel } | ConvertTo-Json -Compress) -TimeoutSec $TimeoutSeconds
} catch {
    throw "Cannot inspect Ollama model '$EmbeddingModel'. $($_.Exception.Message)"
}
if ($metadata.capabilities -notcontains 'embedding') {
    throw "Ollama model '$EmbeddingModel' does not advertise embedding capability. Select an embedding model with -EmbeddingModel."
}

try {
    $response = Invoke-RestMethod -Uri "$ollama/api/embed" -Method Post -ContentType 'application/json' `
        -Body (@{
            model = $EmbeddingModel
            input = 'search_document: A synthetic support case about a router connection.'
            truncate = $false
            keep_alive = '30m'
        } | ConvertTo-Json -Compress) -TimeoutSec $TimeoutSeconds
} catch {
    throw "Ollama embedding generation failed for '$EmbeddingModel'. $($_.Exception.Message)"
}
. (Join-Path $PSScriptRoot 'embedding-helpers.ps1')
Assert-OllamaEmbeddingBatch -Response $response -Count 1
$embedding = @($response.embeddings[0])
Write-Host "Ollama pre-flight passed. Model: $EmbeddingModel; dimensions: $($embedding.Count); digest: $($model[0].digest)."
Write-Host 'A real embedding was generated; the model is kept loaded for 30 minutes.'
Write-Host 'Registry access, SQL readiness, and SQL index capabilities require their separate setup/verification steps.'
