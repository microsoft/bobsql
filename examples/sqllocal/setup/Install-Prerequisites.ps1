[CmdletBinding()]
param(
    [string]$KubectlVersion = 'v1.33.5'
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$Path)

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ })

    if ($entries -notcontains $Path) {
        $newPath = (@($entries) + $Path) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }

    if (($env:Path -split ';') -notcontains $Path) {
        $env:Path = "$Path;$env:Path"
    }
}

function Set-AzureCliCertificateBundle {
    if ($env:REQUESTS_CA_BUNDLE) {
        if (-not (Test-Path -LiteralPath $env:REQUESTS_CA_BUNDLE -PathType Leaf)) {
            throw "REQUESTS_CA_BUNDLE points to a file that does not exist: '$env:REQUESTS_CA_BUNDLE'."
        }

        Write-Host "Using existing Azure CLI CA bundle: $env:REQUESTS_CA_BUNDLE"
        return
    }

    $azureCliRoots = @(
        (Join-Path $env:ProgramFiles 'Microsoft SDKs\Azure\CLI2')
        if (${env:ProgramFiles(x86)}) {
            Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs\Azure\CLI2'
        }
    )
    $certifiBundle = $azureCliRoots |
        ForEach-Object { Join-Path $_ 'Lib\site-packages\certifi\cacert.pem' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $certifiBundle) {
        throw 'Unable to locate the Azure CLI certifi CA bundle.'
    }

    $azureDirectory = Join-Path $env:USERPROFILE '.azure'
    [void][IO.Directory]::CreateDirectory($azureDirectory)
    $windowsBundle = Join-Path $azureDirectory 'windows-root-ca-bundle.pem'
    $bundle = [Text.StringBuilder]::new()
    [void]$bundle.AppendLine([IO.File]::ReadAllText($certifiBundle).TrimEnd())

    $trustedRoots = @(
        Get-ChildItem Cert:\CurrentUser\Root
        Get-ChildItem Cert:\LocalMachine\Root
    ) | Sort-Object Thumbprint -Unique
    foreach ($certificate in $trustedRoots) {
        $base64Certificate = [Convert]::ToBase64String(
            $certificate.RawData,
            [Base64FormattingOptions]::InsertLineBreaks
        )
        [void]$bundle.AppendLine('-----BEGIN CERTIFICATE-----')
        [void]$bundle.AppendLine($base64Certificate)
        [void]$bundle.AppendLine('-----END CERTIFICATE-----')
    }

    [IO.File]::WriteAllText(
        $windowsBundle,
        $bundle.ToString(),
        [Text.Encoding]::ASCII
    )
    $env:REQUESTS_CA_BUNDLE = $windowsBundle
    Write-Host "Configured Azure CLI to use Windows trusted roots: $windowsBundle"
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    if (-not (Test-Administrator)) {
        throw 'Azure CLI is not installed. Reopen PowerShell as Administrator and rerun this script.'
    }

    $installerPath = Join-Path $env:TEMP 'AzureCLI-x64.msi'

    try {
        Write-Host 'Downloading the latest 64-bit Azure CLI installer...'
        $previousProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest `
            -Uri 'https://aka.ms/installazurecliwindowsx64' `
            -OutFile $installerPath
        $ProgressPreference = $previousProgressPreference

        Write-Host 'Installing Azure CLI...'
        $process = Start-Process `
            -FilePath 'msiexec.exe' `
            -ArgumentList '/i', "`"$installerPath`"", '/quiet', '/norestart' `
            -Wait `
            -PassThru

        if ($process.ExitCode -notin 0, 3010) {
            throw "Azure CLI installation failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        $ProgressPreference = $previousProgressPreference
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }

    Write-Host 'Azure CLI installed successfully.' -ForegroundColor Green

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Host 'Azure CLI is installed but is not visible in this PowerShell process.' -ForegroundColor Yellow
        Write-Host 'Close PowerShell, open a new elevated window, and rerun Setup.ps1.' -ForegroundColor Yellow
        return
    }

    Write-Host 'Azure CLI is available in the current PowerShell process; continuing setup.' -ForegroundColor Green
}

Set-AzureCliCertificateBundle

$kubectlDirectory = Join-Path $env:USERPROFILE '.azure-kubectl'
$kubeloginDirectory = Join-Path $env:USERPROFILE '.azure-kubelogin'
$kubectlPath = Join-Path $kubectlDirectory 'kubectl.exe'
$kubeloginPath = Join-Path $kubeloginDirectory 'kubelogin.exe'

$installedKubectlVersion = $null
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    $installedKubectlVersion = (& kubectl version --client=true --output=json | ConvertFrom-Json).clientVersion.gitVersion
}

if ($installedKubectlVersion -ne $KubectlVersion -or -not (Test-Path -LiteralPath $kubeloginPath -PathType Leaf)) {
    Write-Host "Installing kubectl $KubectlVersion and kubelogin..."
    $downloadDirectory = Join-Path $env:TEMP "azure-kubernetes-cli-$([guid]::NewGuid())"
    $kubectlDownloadPath = Join-Path $downloadDirectory 'kubectl.exe'
    $kubeloginArchivePath = Join-Path $downloadDirectory 'kubelogin.zip'
    $kubeloginExtractPath = Join-Path $downloadDirectory 'kubelogin'
    $previousProgressPreference = $ProgressPreference

    try {
        [void][IO.Directory]::CreateDirectory($downloadDirectory)
        [void][IO.Directory]::CreateDirectory($kubectlDirectory)
        [void][IO.Directory]::CreateDirectory($kubeloginDirectory)

        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest `
            -Uri "https://dl.k8s.io/release/$KubectlVersion/bin/windows/amd64/kubectl.exe" `
            -OutFile $kubectlDownloadPath

        $kubeloginRelease = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/Azure/kubelogin/releases/latest' `
            -Headers @{ Accept = 'application/vnd.github+json' }
        $kubeloginVersion = [string]$kubeloginRelease.tag_name
        if (-not $kubeloginVersion) {
            throw 'The latest kubelogin release did not contain a tag name.'
        }

        Invoke-WebRequest `
            -Uri "https://github.com/Azure/kubelogin/releases/download/$kubeloginVersion/kubelogin.zip" `
            -OutFile $kubeloginArchivePath
        Expand-Archive -LiteralPath $kubeloginArchivePath -DestinationPath $kubeloginExtractPath

        $extractedKubeloginPath = Join-Path $kubeloginExtractPath 'bin\windows_amd64\kubelogin.exe'
        if (-not (Test-Path -LiteralPath $extractedKubeloginPath -PathType Leaf)) {
            throw "kubelogin.exe was not found in the expected archive location: '$extractedKubeloginPath'."
        }

        Move-Item -LiteralPath $kubectlDownloadPath -Destination $kubectlPath -Force
        Move-Item -LiteralPath $extractedKubeloginPath -Destination $kubeloginPath -Force
    }
    finally {
        $ProgressPreference = $previousProgressPreference
        Remove-Item -LiteralPath $downloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Add-UserPathEntry -Path $kubectlDirectory
if (Test-Path -LiteralPath $kubeloginPath) {
    Add-UserPathEntry -Path $kubeloginDirectory
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw 'curl.exe was not found. Install the Windows curl package before running the Foundry Local endpoint test.'
}
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'sqlcmd was not found. Install it from https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install and reopen PowerShell.'
}

Write-Host 'Checking the Azure CLI connectedk8s extension...'
$connectedK8sVersion = & az extension list `
    --query "[?name=='connectedk8s'].version | [0]" `
    --output tsv `
    --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to query installed Azure CLI extensions.'
}

if (-not $connectedK8sVersion) {
    Write-Host 'Installing the connectedk8s extension...'
    & az extension add --name connectedk8s --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to install the connectedk8s Azure CLI extension.'
    }

    $connectedK8sVersion = & az extension list `
        --query "[?name=='connectedk8s'].version | [0]" `
        --output tsv `
        --only-show-errors
}

$azVersion = (& az version --output json | ConvertFrom-Json).'azure-cli'
$kubectlVersion = (& kubectl version --client=true --output=json | ConvertFrom-Json).clientVersion.gitVersion
$curlVersion = (& curl.exe --version | Select-Object -First 1)
$sqlcmdPath = (Get-Command sqlcmd).Source

Write-Host ''
Write-Host 'Prerequisites are ready.' -ForegroundColor Green
Write-Host "  Azure CLI:    $azVersion"
Write-Host "  kubectl:      $kubectlVersion"
Write-Host "  connectedk8s: $connectedK8sVersion"
Write-Host "  curl:          $curlVersion"
Write-Host "  sqlcmd:        $sqlcmdPath"
