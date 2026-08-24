# Step 4 - Storage, Flex Consumption function app, identity-based settings,
# role assignments, then deploy the code.
#
# Every connection this app makes is identity-based. There is no Event Hubs
# key, no SignalR access key and no storage key in app settings.

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

function Grant-Role {
    param(
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Scope
    )

    $existing = Invoke-Az @(
        'role', 'assignment', 'list',
        '--assignee', $PrincipalId,
        '--role', $Role,
        '--scope', $Scope
    ) -AllowFailure
    if ($existing -and @($existing).Count -gt 0) {
        Write-Skip "$Role - already assigned"
        return
    }

    foreach ($attempt in 1..6) {
        $r = Invoke-Az @(
            'role', 'assignment', 'create',
            '--assignee-object-id', $PrincipalId,
            '--assignee-principal-type', 'ServicePrincipal',
            '--role', $Role,
            '--scope', $Scope
        ) -AllowFailure
        if ($r) { Write-Ok "$Role - assigned"; return }
        Start-Sleep -Seconds 10
    }
    throw "Could not assign '$Role' at $Scope"
}

Write-Step "Storage account '$StorageAccount'"
$sa = Invoke-Az @('storage', 'account', 'show', '-g', $ResourceGroup, '-n', $StorageAccount) -AllowFailure
if ($sa) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'storage', 'account', 'create',
        '-g', $ResourceGroup,
        '-n', $StorageAccount,
        '-l', $Location,
        '--sku', 'Standard_LRS',
        '--kind', 'StorageV2',
        '--min-tls-version', 'TLS1_2',
        '--allow-blob-public-access', 'false'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step "Function app '$FunctionApp' (Flex Consumption, $FunctionRuntime $FunctionVersion)"
$fn = Invoke-Az @('functionapp', 'show', '-g', $ResourceGroup, '-n', $FunctionApp) -AllowFailure
if ($fn) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'functionapp', 'create',
        '-g', $ResourceGroup,
        '-n', $FunctionApp,
        '--storage-account', $StorageAccount,
        '--flexconsumption-location', $Location,
        '--runtime', $FunctionRuntime,
        '--runtime-version', $FunctionVersion,
        '--assign-identity', '[system]'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step 'Function app managed identity'
$fnPrincipalId = (& az functionapp identity show -g $ResourceGroup -n $FunctionApp --query principalId -o tsv 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fnPrincipalId) -or $fnPrincipalId -eq 'null') {
    Invoke-Az @('functionapp', 'identity', 'assign', '-g', $ResourceGroup, '-n', $FunctionApp) | Out-Null
    $fnPrincipalId = (& az functionapp identity show -g $ResourceGroup -n $FunctionApp --query principalId -o tsv 2>&1 | Out-String).Trim()
}
Write-Ok $fnPrincipalId

Write-Step 'Role assignments for the function identity'
$hubScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.EventHub/namespaces/$EventHubNamespace/eventhubs/$EventHubName"
$nsScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.EventHub/namespaces/$EventHubNamespace"
$srScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.SignalRService/SignalR/$SignalRName"
$saScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$StorageAccount"

Grant-Role -PrincipalId $fnPrincipalId -Role 'Azure Event Hubs Data Receiver' -Scope $hubScope
# The Event Hubs trigger stores checkpoints as consumer-group ownership records.
Grant-Role -PrincipalId $fnPrincipalId -Role 'Azure Event Hubs Data Owner' -Scope $nsScope
# Serverless mode needs BOTH the auth API (accessKey, used by negotiate) and the
# data-plane REST API (SignalR/hub/*, used by the output binding to broadcast).
# 'SignalR App Server' only covers the former -- broadcasting fails with 403.
# 'SignalR Service Owner' is the documented role for Serverless mode.
Grant-Role -PrincipalId $fnPrincipalId -Role 'SignalR Service Owner' -Scope $srScope
Grant-Role -PrincipalId $fnPrincipalId -Role 'Storage Blob Data Owner' -Scope $saScope
Grant-Role -PrincipalId $fnPrincipalId -Role 'Storage Queue Data Contributor' -Scope $saScope
Grant-Role -PrincipalId $fnPrincipalId -Role 'Storage Table Data Contributor' -Scope $saScope

Write-Step "Consumer group '$TriageConsumerGroup' for the triage function"
# A second consumer group means triage reads the same events independently, so
# waiting on the agent never delays the ticket card.
Invoke-Az @('eventhubs', 'eventhub', 'consumer-group', 'create', '-g', $ResourceGroup,
    '--namespace-name', $EventHubNamespace, '--eventhub-name', $EventHubName,
    '-n', $TriageConsumerGroup) -AllowFailure | Out-Null
Write-Ok $TriageConsumerGroup

Write-Step 'App settings (identity-based, no keys)'
$settings = @(
    "EventHubName=$EventHubName",
    "EventHubConnection__fullyQualifiedNamespace=$EventHubFqdn",
    'EventHubConnection__credential=managedidentity',
    "AzureSignalRConnectionString__serviceUri=$SignalRUri",
    'AzureSignalRConnectionString__credential=managedidentity',
    "TriageConsumerGroup=$TriageConsumerGroup"
)
Invoke-Az (@('functionapp', 'config', 'appsettings', 'set', '-g', $ResourceGroup, '-n', $FunctionApp, '--settings') + $settings) | Out-Null
foreach ($s in $settings) { Write-Ok $s }

Write-Step "CORS for the local page ($WebOrigin)"
Invoke-Az @('functionapp', 'cors', 'add', '-g', $ResourceGroup, '-n', $FunctionApp, '--allowed-origins', $WebOrigin) -AllowFailure | Out-Null
Write-Ok $WebOrigin

# The SignalR JS client negotiates with credentials: 'include', so the browser
# requires Access-Control-Allow-Credentials: true. Allow-listing the origin is
# not enough on its own. Azure permits this because the origin is specific, not '*'.
Invoke-Az @('functionapp', 'cors', 'credentials', '-g', $ResourceGroup, '-n', $FunctionApp, '--enable', 'true') -AllowFailure | Out-Null
Write-Ok 'supportCredentials = true'

Write-Step 'Building and publishing the function'
$publishDir = Join-Path $SrcDir 'bin\publish'
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }

Push-Location $SrcDir
try {
    & dotnet publish -c Release -o $publishDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
Write-Ok 'Built'

$zipPath = Join-Path $SrcDir 'bin\publish.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath
Write-Ok "Packaged $([math]::Round((Get-Item $zipPath).Length / 1MB, 2)) MB"

Invoke-Az @(
    'functionapp', 'deployment', 'source', 'config-zip',
    '-g', $ResourceGroup,
    '-n', $FunctionApp,
    '--src', $zipPath
) | Out-Null
Write-Ok 'Deployed'

Write-Step 'Done'
Write-Ok "Function : https://$FunctionApp.azurewebsites.net"
Write-Ok "Negotiate: https://$FunctionApp.azurewebsites.net/api/negotiate"
