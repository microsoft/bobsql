# cleanup.ps1
# Deletes the AKS cluster and resource group for NVIDIA NIM demo
param(
    [string]$ResourceGroup = 'rg-nvidianim-westus2',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host "=== NVIDIA NIM Cleanup ===" -ForegroundColor Cyan
Write-Host "This will delete resource group: $ResourceGroup" -ForegroundColor Red
Write-Host "Including: AKS cluster, GPU nodes, all deployed resources" -ForegroundColor Red
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Type 'yes' to confirm deletion"
    if ($confirm -ne 'yes') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }
}

Write-Host "Deleting resource group $ResourceGroup..." -ForegroundColor Yellow
az group delete --name $ResourceGroup --yes --no-wait

Write-Host "Deletion initiated (running in background). Resource group will be gone in ~5 minutes." -ForegroundColor Green
Write-Host ""
Write-Host "Also clean up SQL objects if desired:" -ForegroundColor Yellow
Write-Host "  DROP EXTERNAL MODEL NIMEmbeddingModel;"
