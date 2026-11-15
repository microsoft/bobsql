[CmdletBinding()]
param(
    [uri]$Endpoint = 'https://inference-internal-gateway-istio.foundry-local-operator.svc.cluster.local:443/gpt-oss-20b/v1/chat/completions'
)

$ErrorActionPreference = 'Stop'

if (-not $Endpoint.IsAbsoluteUri -or $Endpoint.Scheme -ne 'https' -or $Endpoint.UserInfo) {
    throw 'Endpoint must be an absolute HTTPS URL without embedded credentials.'
}

$curl = Get-Command curl.exe -ErrorAction Stop

Write-Host "Testing DNS, routing, and trusted HTTPS from this machine: $Endpoint"
Write-Host 'This unauthenticated GET does not invoke the model or change SQL configuration.'

& $curl.Source `
    --verbose `
    --ssl-revoke-best-effort `
    --connect-timeout 10 `
    --max-time 20 `
    --output NUL `
    --write-out '\nHTTP status: %{http_code}\nRemote IP: %{remote_ip}\n' `
    $Endpoint.AbsoluteUri

$curlExitCode = $LASTEXITCODE
if ($curlExitCode -ne 0) {
    throw "HTTPS probe failed with curl exit code $curlExitCode. See the full curl error above."
}

Write-Host 'HTTPS completed with certificate validation enabled. Check the HTTP status above.'
Write-Host 'An HTTP error such as 401, 403, or 405 still proves HTTPS reachability, not authenticated chat or SQL connectivity.'
