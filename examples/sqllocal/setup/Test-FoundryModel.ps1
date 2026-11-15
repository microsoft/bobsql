[CmdletBinding()]
param(
    [ValidateSet('Chat', 'Embedding')]
    [string]$Mode = 'Chat',
    [string]$KubeconfigPath = 'C:\setup\caldova-admin.kubeconfig',
    [string]$FoundryNamespace = 'foundry-local-operator',
    [string]$ExternalIPAddress = '192.0.2.10'
)

$ErrorActionPreference = 'Stop'
$deploymentName = if ($Mode -eq 'Chat') { 'gpt-oss-20b' } else { 'nemotron-3-embed-1b-bf16' }
$address = $null
if (-not [Net.IPAddress]::TryParse($ExternalIPAddress, [ref]$address) -or
    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'ExternalIPAddress must be an IPv4 address covered by the Gateway certificate.'
}
if (-not (Test-Path -LiteralPath $KubeconfigPath -PathType Leaf)) {
    throw "Protected kubeconfig was not found at '$KubeconfigPath'."
}
$kubectl = Get-Command kubectl -ErrorAction Stop
$curl = Get-Command curl.exe -ErrorAction Stop
$baseUrl = "https://$ExternalIPAddress/$deploymentName/v1"

function ConvertTo-CurlConfigValue {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -match '[\r\n]') {
        throw 'Curl configuration values must not contain line breaks.'
    }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Invoke-FoundryRequest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Body
    )

    $config = 'header = "api-key: {0}"' -f (ConvertTo-CurlConfigValue $apiKey)
    if ($Body) {
        $config += "`n" + 'header = "Content-Type: application/json"'
        $config += "`n" + ('data = "{0}"' -f (ConvertTo-CurlConfigValue $Body))
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $raw = @($config | & $curl.Source `
        --config - `
        --silent `
        --show-error `
        --fail-with-body `
        --ssl-revoke-best-effort `
        --connect-timeout 10 `
        --max-time 180 `
        --write-out '\n%{http_code}' `
        "$baseUrl/$Path") -join "`n"
    $curlExitCode = $LASTEXITCODE
    $timer.Stop()
    $separator = $raw.LastIndexOf("`n")
    if ($separator -lt 0) {
        Write-Host $raw
        throw "No HTTP status was returned; curl exit code $curlExitCode."
    }
    $responseBody = $raw.Substring(0, $separator)
    $httpStatus = $raw.Substring($separator + 1).Trim()
    Write-Host "$deploymentName/$Path : HTTP $httpStatus, $($timer.ElapsedMilliseconds) ms"
    if ($curlExitCode -ne 0 -or $httpStatus -ne '200') {
        Write-Host $responseBody
        throw "Foundry request failed: HTTP $httpStatus, curl exit code $curlExitCode."
    }
    return $responseBody | ConvertFrom-Json
}

try {
    $encodedApiKey = & $kubectl.Source `
        --kubeconfig $KubeconfigPath `
        get secret "$deploymentName-api-keys" `
        --namespace $FoundryNamespace `
        --request-timeout=15s `
        --output 'jsonpath={.data.primary-key}'
    if ($LASTEXITCODE -ne 0 -or -not $encodedApiKey) {
        throw "Unable to retrieve the API key for '$deploymentName'."
    }
    $apiKey = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedApiKey))

    $modelList = Invoke-FoundryRequest -Path 'models'
    $models = @($modelList.data | Where-Object id -eq $deploymentName)
    if ($models.Count -ne 1) {
        throw "Expected exactly one served model named '$deploymentName'."
    }
    Write-Host "Served model ID: $($models[0].id)"

    if ($Mode -eq 'Chat') {
        $payload = @{
            model = $models[0].id
            messages = @(@{
                role = 'user'
                content = 'Reply with exactly: Caldova HTTPS is working.'
            })
            max_tokens = 256
            temperature = 0
        } | ConvertTo-Json -Depth 5 -Compress
        $response = Invoke-FoundryRequest -Path 'chat/completions' -Body $payload
        $choices = @($response.choices)
        if ($choices.Count -ne 1 -or
            [string]::IsNullOrWhiteSpace($choices[0].message.content)) {
            Write-Host ($response | ConvertTo-Json -Depth 10)
            throw 'Chat response did not contain one nonempty assistant message.'
        }
        Write-Host "Chat response: $($choices[0].message.content)" -ForegroundColor Green
    }
    else {
        $payload = @{
            model = $models[0].id
            input = @('Synthetic transport note: patient reports shortness of breath.')
            encoding_format = 'float'
        } | ConvertTo-Json -Depth 5 -Compress
        $response = Invoke-FoundryRequest -Path 'embeddings' -Body $payload
        $items = @($response.data)
        if ($items.Count -ne 1 -or $items[0].index -ne 0 -or
            -not ($items[0].embedding -is [array]) -or $items[0].embedding.Count -eq 0) {
            Write-Host ($response | ConvertTo-Json -Depth 10)
            throw 'Embedding response did not contain one nonempty float vector at index 0.'
        }
        foreach ($value in $items[0].embedding) {
            if (-not ($value -is [double] -or $value -is [single] -or
                $value -is [decimal] -or $value -is [int] -or $value -is [long]) -or
                [double]::IsNaN([double]$value) -or [double]::IsInfinity([double]$value)) {
                throw 'Embedding response contained a nonnumeric or nonfinite value.'
            }
        }
        Write-Host "Embedding dimensions: $($items[0].embedding.Count)" -ForegroundColor Green
    }
    Write-Host 'Authenticated HTTPS inference passed. SQL connectivity is not tested by this script.' -ForegroundColor Green
}
finally {
    $apiKey = $null
    $encodedApiKey = $null
}
