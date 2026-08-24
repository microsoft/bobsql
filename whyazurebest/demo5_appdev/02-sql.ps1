# Step 2 - Azure SQL logical server and Hyperscale database.
#
# Entra-only authentication: there is no SQL admin login and no password. The
# server gets a system-assigned managed identity, which is what Change Event
# Streaming later uses to authenticate to Event Hubs.

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step 'Signed-in Entra identity (becomes the SQL admin)'
$me = Invoke-Az @('ad', 'signed-in-user', 'show')
$adminName = $me.userPrincipalName
$adminSid = $me.id
Write-Ok "$adminName ($adminSid)"

Write-Step "Logical server '$ServerName' (Entra-only, system-assigned identity)"
$srv = Invoke-Az @('sql', 'server', 'show', '-g', $ResourceGroup, '-n', $ServerName) -AllowFailure
if ($srv) {
    if ($srv.location -ne $Location) {
        Write-Fail "Exists in '$($srv.location)' but this demo needs '$Location'"
        throw "Delete it first: az sql server delete -g $ResourceGroup -n $ServerName"
    }
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'sql', 'server', 'create',
        '-g', $ResourceGroup,
        '-n', $ServerName,
        '-l', $Location,
        '--enable-ad-only-auth',
        '--external-admin-principal-type', 'User',
        '--external-admin-name', $adminName,
        '--external-admin-sid', $adminSid,
        '--assign-identity',
        '--minimal-tls-version', '1.2'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step 'Server managed identity'
$principalId = (& az sql server show -g $ResourceGroup -n $ServerName --query identity.principalId -o tsv 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId) -or $principalId -eq 'null') {
    throw "The server has no system-assigned identity. Run: az sql server update -g $ResourceGroup -n $ServerName --assign-identity"
}
Write-Ok $principalId

Write-Step "Grant the server 'Azure Event Hubs Data Sender' on '$EventHubName'"
$hubScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.EventHub/namespaces/$EventHubNamespace/eventhubs/$EventHubName"
$existing = Invoke-Az @(
    'role', 'assignment', 'list',
    '--assignee', $principalId,
    '--role', 'Azure Event Hubs Data Sender',
    '--scope', $hubScope
) -AllowFailure
if ($existing -and @($existing).Count -gt 0) {
    Write-Skip 'Already assigned'
}
else {
    # Role assignment on a brand new identity can race Entra replication.
    $assigned = $false
    foreach ($attempt in 1..6) {
        $r = Invoke-Az @(
            'role', 'assignment', 'create',
            '--assignee-object-id', $principalId,
            '--assignee-principal-type', 'ServicePrincipal',
            '--role', 'Azure Event Hubs Data Sender',
            '--scope', $hubScope
        ) -AllowFailure
        if ($r) { $assigned = $true; break }
        Write-Skip "Entra has not replicated the identity yet (attempt $attempt), waiting 10s"
        Start-Sleep -Seconds 10
    }
    if (-not $assigned) { throw 'Could not assign Azure Event Hubs Data Sender to the server identity.' }
    Write-Ok 'Assigned'
}

Write-Step "Hyperscale database '$DatabaseName' (serverless, Gen5, 2 vCore)"
$db = Invoke-Az @('sql', 'db', 'show', '-g', $ResourceGroup, '-s', $ServerName, '-n', $DatabaseName) -AllowFailure
if ($db) {
    Write-Skip "Already exists ($($db.currentServiceObjectiveName))"
}
else {
    Invoke-Az @(
        'sql', 'db', 'create',
        '-g', $ResourceGroup,
        '-s', $ServerName,
        '-n', $DatabaseName,
        '-e', 'Hyperscale',
        '-f', 'Gen5',
        '-c', '2',
        '--compute-model', 'Serverless',
        '--auto-pause-delay', '60',
        '--ha-replicas', '0',
        '--backup-storage-redundancy', 'Local'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step 'Firewall rule for this laptop (needed to run the DDL)'
Set-PresenterFirewall
Write-Ok 'Server reachable as the Entra admin'

Write-Step 'Done'
Write-Ok "Server : $ServerFqdn"
Write-Ok "Admin  : $adminName (Entra-only, no SQL login exists)"
