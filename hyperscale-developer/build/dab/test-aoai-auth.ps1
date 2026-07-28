$ErrorActionPreference = 'Stop'
$tok = az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
$body = '{"messages":[{"role":"user","content":"reply with the single word: ok"}],"max_completion_tokens":50}'
try {
    $r = Invoke-RestMethod -Uri "https://collierhealth-ai.openai.azure.com/openai/deployments/gpt-5/chat/completions?api-version=2025-04-01-preview" -Method Post -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json' -Body $body
    Write-Host ("AOAI OK -> " + $r.choices[0].message.content)
}
catch {
    Write-Host ("AOAI HTTP " + $_.Exception.Response.StatusCode.value__ + ": " + $_.ErrorDetails.Message)
}
