# deploy-nim.ps1
# Deploys NVIDIA NIM containers (chat + embedding) to AKS
# Requires: $env:NGC_API_KEY set, kubectl context pointing to aks-nvidianim
param(
    [string]$NgcApiKey = $env:NGC_API_KEY
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $NgcApiKey) {
    Write-Error "NGC_API_KEY not set. Get one from https://org.ngc.nvidia.com/ and set `$env:NGC_API_KEY"
    return
}

Write-Host "=== Deploying NVIDIA NIM to AKS ===" -ForegroundColor Cyan

# Create NGC registry pull secret (for pulling NIM images from nvcr.io)
Write-Host "Creating NGC registry pull secret..." -ForegroundColor Yellow
kubectl create secret docker-registry ngc-registry `
    --docker-server=nvcr.io `
    --docker-username='$oauthtoken' `
    --docker-password=$NgcApiKey `
    --dry-run=client -o yaml | kubectl apply -f -

# Create NGC API key secret (NIM containers use this at runtime)
Write-Host "Creating NGC API key secret..." -ForegroundColor Yellow
kubectl create secret generic ngc-secret `
    --from-literal=NGC_API_KEY=$NgcApiKey `
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy NIM containers
Write-Host "Deploying NIM embedding model (nv-embedqa-e5-v5)..." -ForegroundColor Yellow
kubectl apply -f "$scriptDir\k8s\nim-embedding.yaml"

Write-Host "Deploying NIM chat model (llama-3.2-3b-instruct)..." -ForegroundColor Yellow
kubectl apply -f "$scriptDir\k8s\nim-chat.yaml"

# Deploy ingress
Write-Host "Deploying ingress..." -ForegroundColor Yellow
kubectl apply -f "$scriptDir\k8s\ingress.yaml"

# Wait for pods
Write-Host ""
Write-Host "Waiting for pods to start (NIM model download takes 5-10 min)..." -ForegroundColor Yellow
Write-Host "Monitor with: kubectl get pods -w"
Write-Host ""

kubectl get pods -o wide
Write-Host ""

# Show ingress IP (may take a minute to assign)
Write-Host "Checking ingress IP..." -ForegroundColor Yellow
$ip = kubectl get ingress nim-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
if ($ip) {
    Write-Host "Ingress IP: $ip" -ForegroundColor Green
    Write-Host "Embedding endpoint: http://$ip/v1/embeddings"
    Write-Host "Chat endpoint:     http://$ip/v1/chat/completions"
} else {
    Write-Host "Ingress IP not assigned yet. Check with:" -ForegroundColor Yellow
    Write-Host "  kubectl get ingress nim-ingress"
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Wait for pods to be Ready: kubectl get pods -w"
Write-Host "  2. Get ingress IP: kubectl get ingress nim-ingress"
Write-Host "  3. Test: .\test-embedding.ps1 -IngressIP <IP>"
Write-Host "  4. Test: .\test-chat.ps1 -IngressIP <IP>"
