[CmdletBinding()]
param(
    [string]$SqlServiceName = 'MSSQLSERVER',
    [string]$KubeconfigPath = (Join-Path $PSScriptRoot 'caldova-admin.kubeconfig'),
    [string]$FoundryNamespace = 'foundry-local-operator',
    [string]$GatewayTlsSecret = 'inference-external-gateway-ip-tls'
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-KubernetesReady {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $script:KubernetesReadyOutput = & kubectl `
            --kubeconfig $KubeconfigPath `
            get namespace $FoundryNamespace `
            --request-timeout=15s `
            --output name 2>$null
        return $LASTEXITCODE -eq 0 -and $script:KubernetesReadyOutput -eq "namespace/$FoundryNamespace"
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

if (-not (Test-Administrator)) {
    throw 'Run Setup.ps1 from an elevated PowerShell window.'
}

$installScript = Join-Path $PSScriptRoot 'Install-Prerequisites.ps1'
$certificateScript = Join-Path $PSScriptRoot 'Import-GatewayRootCertificate.ps1'

Write-Host 'Step 1 of 3: Installing and checking prerequisites...' -ForegroundColor Cyan
& $installScript

Write-Host ''
Write-Host 'Step 2 of 3: Connecting directly to the existing Kubernetes cluster...' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $KubeconfigPath -PathType Leaf)) {
    throw "The admin kubeconfig was not found at '$KubeconfigPath'."
}
if (-not (Test-KubernetesReady)) {
    throw "The Kubernetes API is unavailable through '$KubeconfigPath'. Last response: $KubernetesReadyOutput"
}
Write-Host "The Kubernetes API is ready through '$KubeconfigPath'." -ForegroundColor Green

Write-Host ''
Write-Host 'Step 3 of 3: Trusting the existing Gateway certificate...' -ForegroundColor Cyan
& $certificateScript `
    -KubeconfigPath $KubeconfigPath `
    -FoundryNamespace $FoundryNamespace `
    -GatewayTlsSecret $GatewayTlsSecret `
    -SqlServiceName $SqlServiceName

Write-Host ''
Write-Host 'Setup completed successfully.' -ForegroundColor Green
Write-Host 'Run test.ps1 separately to configure and test the SQL path.'
