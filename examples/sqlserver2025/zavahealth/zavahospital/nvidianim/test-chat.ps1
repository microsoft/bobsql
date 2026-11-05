# test-chat.ps1
# Test NIM chat completion endpoint on AKS
param(
    [string]$IngressIP
)

if (-not $IngressIP) {
    $IngressIP = kubectl get ingress nim-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if (-not $IngressIP) {
        Write-Error "No IngressIP provided and could not detect from cluster. Usage: .\test-chat.ps1 -IngressIP <IP>"
        return
    }
    Write-Host "Auto-detected ingress IP: $IngressIP" -ForegroundColor Yellow
}

$body = @{
    model    = "meta/llama-3.2-3b-instruct"
    messages = @(
        @{ role = "system"; content = "You are a helpful assistant." }
        @{ role = "user";   content = "What is a vector embedding in one sentence?" }
    )
    max_tokens = 256
} | ConvertTo-Json -Depth 4

Write-Host "Testing chat endpoint at http://$IngressIP/v1/chat/completions ..." -ForegroundColor Cyan

$response = Invoke-RestMethod -Uri "http://$IngressIP/v1/chat/completions" -Method Post -ContentType "application/json" -Body $body

Write-Host "Model: $($response.model)" -ForegroundColor Green
Write-Host "Finish reason: $($response.choices[0].finish_reason)"
Write-Host ""
Write-Host "Response:"
Write-Host $response.choices[0].message.content
