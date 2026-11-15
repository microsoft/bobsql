[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ClusterName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,

    [string]$Namespace,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Subscription,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [switch]$SkipLogin,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

Assert-Command -Name 'az'
Assert-Command -Name 'kubectl'

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
}

if (-not $SkipLogin) {
    Write-Host "Signing in to tenant '$Tenant'..."
    & az login --tenant $Tenant --only-show-errors --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Azure sign-in failed for tenant '$Tenant'."
    }
}

if ($Subscription) {
    Write-Host "Selecting subscription '$Subscription'..."
    & az account set --subscription $Subscription
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to select subscription '$Subscription'."
    }
}

Write-Host "Confirming access to Arc cluster '$ClusterName' in resource group '$ResourceGroup'..."
& az connectedk8s show `
    --name $ClusterName `
    --resource-group $ResourceGroup `
    --only-show-errors `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'The cluster was not found or the signed-in account cannot access it.'
}

if ($ValidateOnly) {
    Write-Host 'Prerequisite and Azure resource access checks passed.' -ForegroundColor Green
    return
}

Write-Host ''
Write-Host 'Keep this terminal open while using kubectl.' -ForegroundColor Yellow
Write-Host 'After the proxy reports that it is ready, run these commands in a second terminal:'
Write-Host '  kubectl get nodes'
Write-Host '  kubectl get namespaces'
if ($Namespace) {
    Write-Host "  kubectl --namespace '$Namespace' get pods"
}
else {
    Write-Host "  kubectl --namespace '<your-namespace>' get pods"
}
Write-Host ''
Write-Host "Starting the proxy for '$ClusterName'..."

& az connectedk8s proxy `
    --name $ClusterName `
    --resource-group $ResourceGroup

if ($LASTEXITCODE -ne 0) {
    throw "The connectedk8s proxy exited with code $LASTEXITCODE."
}
