[CmdletBinding()]
param(
    [string]$CertificatePath = (Join-Path $PSScriptRoot 'lab-root-ca.crt'),
    [string]$KubeconfigPath = (Join-Path $PSScriptRoot 'caldova-admin.kubeconfig'),
    [string]$FoundryNamespace = 'foundry-local-operator',
    [string]$GatewayTlsSecret = 'inference-external-gateway-ip-tls',
    [string]$SqlServiceName = 'MSSQLSERVER'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window.'
}

if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        throw "The Gateway root certificate was not found at '$CertificatePath', and kubectl is unavailable."
    }

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $namespace = & kubectl `
            --kubeconfig $KubeconfigPath `
            get namespace $FoundryNamespace `
            --output name 2>$null
        $namespaceExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($namespaceExitCode -ne 0 -or $namespace -ne "namespace/$FoundryNamespace") {
        throw "The Kubernetes API is unavailable through '$KubeconfigPath'."
    }

    $encodedCertificateChain = & kubectl `
        --kubeconfig $KubeconfigPath `
        get secret $GatewayTlsSecret `
        --namespace $FoundryNamespace `
        --output 'jsonpath={.data.tls\.crt}'
    if ($LASTEXITCODE -ne 0 -or -not $encodedCertificateChain) {
        throw "Unable to read the public certificate chain from '$FoundryNamespace/$GatewayTlsSecret'."
    }

    $certificateChain = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($encodedCertificateChain)
    )
    $pemCertificates = [regex]::Matches(
        $certificateChain,
        '(?s)-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----'
    )
    $rootCertificate = $null
    foreach ($pemCertificate in $pemCertificates) {
        $certificateBytes = [Convert]::FromBase64String(
            ($pemCertificate.Groups[1].Value -replace '\s', '')
        )
        $candidate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $certificateBytes
        )
        if ($candidate.Subject -eq $candidate.Issuer) {
            $rootCertificate = $candidate
            break
        }
    }

    if (-not $rootCertificate) {
        throw "No self-signed root CA was found in '$FoundryNamespace/$GatewayTlsSecret'."
    }

    [IO.File]::WriteAllBytes(
        $CertificatePath,
        $rootCertificate.Export(
            [Security.Cryptography.X509Certificates.X509ContentType]::Cert
        )
    )
    Write-Host "Saved the public Gateway root CA to '$CertificatePath'."
}

$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
$existingCertificate = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object Thumbprint -eq $certificate.Thumbprint |
    Select-Object -First 1

if ($existingCertificate) {
    Write-Host "Gateway root CA is already trusted: $($certificate.Thumbprint)" -ForegroundColor Green
}
else {
    Import-Certificate `
        -FilePath $CertificatePath `
        -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Host "Imported Gateway root CA: $($certificate.Thumbprint)" -ForegroundColor Green
}

$sqlService = Get-Service -Name $SqlServiceName -ErrorAction Stop
if ($sqlService.Status -eq 'Running') {
    $runningDependents = @($sqlService.DependentServices |
        Where-Object Status -eq 'Running')

    foreach ($dependent in $runningDependents) {
        Stop-Service -Name $dependent.Name
    }

    Restart-Service -Name $SqlServiceName

    foreach ($dependent in $runningDependents) {
        Start-Service -Name $dependent.Name
    }

    Write-Host "Restarted SQL Server service '$SqlServiceName'." -ForegroundColor Green
    if ($runningDependents.Count -gt 0) {
        Write-Host "Restored dependent services: $($runningDependents.Name -join ', ')"
    }
}
else {
    Write-Host "SQL Server service '$SqlServiceName' is $($sqlService.Status); it was not started." -ForegroundColor Yellow
}
