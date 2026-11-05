# create-aks-cluster.ps1
# Creates AKS cluster with GPU node pool (2x NC4as_T4_v3) and App Routing
param(
    [string]$ResourceGroup = 'rg-nvidianim-westus2',
    [string]$Location = 'westus2',
    [string]$ClusterName = 'aks-nvidianim',
    [Parameter(Mandatory = $true)]
    [string]$Subscription  # Pass your Azure subscription GUID: -Subscription <guid>
)

$ErrorActionPreference = 'Stop'

# Helper: run az command and fail on error
function Invoke-Az {
    $output = & az @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "az command failed (exit code $LASTEXITCODE): $output"
        throw "az command failed"
    }
    return $output
}

Write-Host "=== NVIDIA NIM on AKS — Cluster Creation ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location:       $Location"
Write-Host "Cluster:        $ClusterName"
Write-Host ""

# Set subscription
Write-Host "Setting subscription..." -ForegroundColor Yellow
Invoke-Az account set --subscription $Subscription

# Create resource group
Write-Host "Creating resource group..." -ForegroundColor Yellow
Invoke-Az group create --name $ResourceGroup --location $Location -o none

# Create AKS cluster with system node pool (small CPU nodes) + App Routing
Write-Host "Creating AKS cluster (this takes ~5 minutes)..." -ForegroundColor Yellow
Invoke-Az aks create `
    --resource-group $ResourceGroup `
    --name $ClusterName `
    --location $Location `
    --node-count 1 `
    --node-vm-size Standard_DS2_v2 `
    --enable-app-routing `
    --enable-oidc-issuer `
    --generate-ssh-keys `
    --os-sku AzureLinux `
    -o none

# Add GPU node pool — 2x NC4as_T4_v3 (1x T4 16GB each)
Write-Host "Adding GPU node pool (2x NC4as_T4_v3)..." -ForegroundColor Yellow
Invoke-Az aks nodepool add `
    --resource-group $ResourceGroup `
    --cluster-name $ClusterName `
    --name gpupool `
    --node-count 2 `
    --node-vm-size Standard_NC4as_T4_v3 `
    --node-taints "nvidia.com/gpu=present:NoSchedule" `
    --labels gpu-type=nvidia-t4 `
    --os-sku AzureLinux `
    -o none

# Get credentials
Write-Host "Getting cluster credentials..." -ForegroundColor Yellow
Invoke-Az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing

# Install kubectl if not available
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "Installing kubectl via az aks install-cli..." -ForegroundColor Yellow
    az aks install-cli
    # Add to PATH in current session (installer updates user PATH but current session doesn't see it)
    $env:PATH += ";$HOME\.azure-kubectl;$HOME\.azure-kubelogin"
}

# Install NVIDIA device plugin (required for GPU scheduling)
Write-Host "Installing NVIDIA device plugin..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml

# Verify GPU nodes
Write-Host ""
Write-Host "=== Cluster Ready ===" -ForegroundColor Green
kubectl get nodes -o wide
Write-Host ""
Write-Host "GPU node pool (look for NC4as_T4_v3):"
kubectl get nodes -l gpu-type=nvidia-t4
Write-Host ""
Write-Host "Next: Set NGC_API_KEY and run deploy-nim.ps1"
