# test-embedding.ps1
# Test NIM embedding endpoint on AKS
param(
    [string]$IngressIP
)

if (-not $IngressIP) {
    $IngressIP = kubectl get ingress nim-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if (-not $IngressIP) {
        Write-Error "No IngressIP provided and could not detect from cluster. Usage: .\test-embedding.ps1 -IngressIP <IP>"
        return
    }
    Write-Host "Auto-detected ingress IP: $IngressIP" -ForegroundColor Yellow
}

$body = @{
    input = "mountain bike for rugged terrain"
    model = "nvidia/nv-embedqa-e5-v5"
    input_type = "query"
} | ConvertTo-Json

Write-Host "Testing embedding endpoint at http://$IngressIP/v1/embeddings ..." -ForegroundColor Cyan

$response = Invoke-RestMethod -Uri "http://$IngressIP/v1/embeddings" -Method Post -ContentType "application/json" -Body $body

Write-Host "Model: $($response.model)" -ForegroundColor Green
Write-Host "Embedding dimension: $($response.data[0].embedding.Count)"
Write-Host "First 10 values: $($response.data[0].embedding[0..9] -join ', ')"
