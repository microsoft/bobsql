# Step 1 - Resource group, Event Hubs and SignalR.
#
# Event Hubs must be Standard or higher: Change Event Streaming talks Kafka on
# port 9093, and the Basic tier does not support the Kafka protocol.

. "$PSScriptRoot\00-config.ps1"

Write-Step "Subscription"
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
Write-Ok $SubscriptionId

Write-Step "Resource group '$ResourceGroup' in $Location"
$rg = Invoke-Az @('group', 'show', '-n', $ResourceGroup) -AllowFailure
if ($rg) {
    if ($rg.location -ne $Location) {
        Write-Fail "Exists in '$($rg.location)' but this demo needs '$Location'"
        throw "Delete it first: az group delete -n $ResourceGroup"
    }
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @('group', 'create', '-n', $ResourceGroup, '-l', $Location) | Out-Null
    Write-Ok 'Created'
}

Write-Step "Event Hubs namespace '$EventHubNamespace' (Standard - Kafka needs it)"
$ns = Invoke-Az @('eventhubs', 'namespace', 'show', '-g', $ResourceGroup, '-n', $EventHubNamespace) -AllowFailure
if ($ns) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'eventhubs', 'namespace', 'create',
        '-g', $ResourceGroup,
        '-n', $EventHubNamespace,
        '-l', $Location,
        '--sku', 'Standard',
        '--minimum-tls-version', '1.2'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step "Event hub '$EventHubName'"
$hub = Invoke-Az @(
    'eventhubs', 'eventhub', 'show',
    '-g', $ResourceGroup,
    '--namespace-name', $EventHubNamespace,
    '-n', $EventHubName
) -AllowFailure
if ($hub) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'eventhubs', 'eventhub', 'create',
        '-g', $ResourceGroup,
        '--namespace-name', $EventHubNamespace,
        '-n', $EventHubName,
        '--partition-count', '1',
        '--cleanup-policy', 'Delete',
        '--retention-time-in-hours', '1'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step "SignalR '$SignalRName' (serverless mode)"
$sr = Invoke-Az @('signalr', 'show', '-g', $ResourceGroup, '-n', $SignalRName) -AllowFailure
if ($sr) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'signalr', 'create',
        '-g', $ResourceGroup,
        '-n', $SignalRName,
        '-l', $Location,
        '--sku', 'Free_F1',
        '--service-mode', 'Serverless'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step 'Done'
Write-Ok "Event hub  : $EventHubFqdn/$EventHubName"
Write-Ok "SignalR    : $SignalRUri"
