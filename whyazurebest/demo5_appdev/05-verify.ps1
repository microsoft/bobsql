# Step 5 - Pre-flight. Confirms the demo is in its opening state.
#
# Exit 0 = ready to present. Exit 1 = something drifted.

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Check, [bool]$Pass, [string]$Detail)
    $results.Add([pscustomobject]@{
            Result = $(if ($Pass) { 'PASS' } else { 'FAIL' })
            Check  = $Check
            Detail = $Detail
        })
}

function Show-Section {
    param([string]$Title, [int]$From)
    Write-Host ''
    Write-Host "==> $Title" -ForegroundColor Cyan
    Write-Host ''
    for ($i = $From; $i -lt $results.Count; $i++) {
        $r = $results[$i]
        $color = if ($r.Result -eq 'PASS') { 'Green' } else { 'Red' }
        Write-Host ('    {0} | {1,-42} | {2}' -f $r.Result, $r.Check, $r.Detail) -ForegroundColor $color
    }
}

# --- Messaging ---------------------------------------------------------------
$mark = $results.Count

$ns = Invoke-Az @('eventhubs', 'namespace', 'show', '-g', $ResourceGroup, '-n', $EventHubNamespace) -AllowFailure
Add-Result 'Event Hubs namespace exists' ($null -ne $ns) $(if ($ns) { $EventHubFqdn } else { 'absent' })
Add-Result 'Namespace tier supports Kafka' ($ns -and $ns.sku.name -ne 'Basic') $(if ($ns) { $ns.sku.name } else { 'n/a' })

$hub = Invoke-Az @('eventhubs', 'eventhub', 'show', '-g', $ResourceGroup, '--namespace-name', $EventHubNamespace, '-n', $EventHubName) -AllowFailure
Add-Result 'Event hub exists' ($null -ne $hub) $(if ($hub) { $EventHubName } else { 'absent' })

$sr = Invoke-Az @('signalr', 'show', '-g', $ResourceGroup, '-n', $SignalRName) -AllowFailure
Add-Result 'SignalR exists' ($null -ne $sr) $(if ($sr) { $SignalRName } else { 'absent' })
Add-Result 'SignalR is in Serverless mode' ($sr -and $sr.features.Where({ $_.flag -eq 'ServiceMode' }).value -eq 'Serverless') $(if ($sr) { ($sr.features | Where-Object flag -EQ 'ServiceMode').value } else { 'n/a' })

Show-Section 'Messaging' $mark

# --- SQL control plane -------------------------------------------------------
$mark = $results.Count

$srv = Invoke-Az @('sql', 'server', 'show', '-g', $ResourceGroup, '-n', $ServerName) -AllowFailure
Add-Result 'Logical server exists' ($null -ne $srv) $(if ($srv) { $ServerFqdn } else { 'absent' })

$adOnly = Invoke-Az @('sql', 'server', 'ad-only-auth', 'get', '-g', $ResourceGroup, '-n', $ServerName) -AllowFailure
Add-Result 'Entra-only authentication is ON' ($adOnly -and $adOnly.azureAdOnlyAuthentication) $(if ($adOnly) { "$($adOnly.azureAdOnlyAuthentication)" } else { 'unknown' })

$srvPrincipal = if ($srv) { $srv.identity.principalId } else { $null }
Add-Result 'Server has a system-assigned identity' (-not [string]::IsNullOrWhiteSpace($srvPrincipal)) $(if ($srvPrincipal) { $srvPrincipal } else { 'none' })

$hubScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.EventHub/namespaces/$EventHubNamespace/eventhubs/$EventHubName"
$senderRole = if ($srvPrincipal) {
    Invoke-Az @('role', 'assignment', 'list', '--assignee', $srvPrincipal, '--role', 'Azure Event Hubs Data Sender', '--scope', $hubScope) -AllowFailure
}
else { $null }
Add-Result 'Server identity can send to the event hub' ($senderRole -and @($senderRole).Count -gt 0) $(if ($senderRole -and @($senderRole).Count -gt 0) { 'Azure Event Hubs Data Sender' } else { 'missing' })

$db = Invoke-Az @('sql', 'db', 'show', '-g', $ResourceGroup, '-s', $ServerName, '-n', $DatabaseName) -AllowFailure
Add-Result 'Hyperscale database exists' ($db -and $db.edition -eq 'Hyperscale') $(if ($db) { "$($db.edition) / $($db.currentServiceObjectiveName)" } else { 'absent' })

Show-Section 'SQL control plane' $mark

# --- Data plane --------------------------------------------------------------
$mark = $results.Count

$sqlsimOk = Test-Path $script:SqlSim
Add-Result 'sqlsim is available' $sqlsimOk $(if ($sqlsimOk) { $script:SqlSim } else { 'not found' })

if ($sqlsimOk) {
    # Confirm the firewall still admits this laptop before anything else runs.
    # If a tunnelling client is active the server sees a different address, and
    # this is where we want to find that out - on the ground, not on stage.
    try {
        Set-PresenterFirewall
        Add-Result 'Firewall admits this laptop' $true 'reachable'
    }
    catch {
        Add-Result 'Firewall admits this laptop' $false $_.Exception.Message.Split("`n")[0]
    }

    try {
        $who = Invoke-Sql -Query 'SELECT SUSER_SNAME();'
        Add-Result 'Connects to the database as Entra' $true $who
    }
    catch {
        Add-Result 'Connects to the database as Entra' $false $_.Exception.Message.Split("`n")[0]
        $who = $null
    }

    if ($who) {
        $tbl = Invoke-Sql -Query "SELECT CASE WHEN OBJECT_ID('dbo.SupportTicket','U') IS NULL THEN 'absent' ELSE 'present' END;"
        Add-Result 'dbo.SupportTicket exists' ($tbl -eq 'present') $tbl

        # A CES-skipped type here would make the payload vanish from the event.
        $banned = Invoke-Sql -Query @"
SELECT ISNULL(STRING_AGG(c.name + ' (' + t.name + ')', ', '), 'none')
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.SupportTicket','U')
  AND t.name IN ('json','xml','vector','sql_variant','geography','geometry','text','ntext','image','timestamp');
"@
        Add-Result 'No CES-skipped column types' ($banned -eq 'none') $banned

        $groups = Invoke-Sql -Query 'EXEC sys.sp_help_change_event_stream_groups;'
        $groupOk = $groups -match [regex]::Escape($StreamGroupName)
        Add-Result 'Stream group exists' $groupOk $(if ($groupOk) { $StreamGroupName } else { 'not found' })

        $tables = Invoke-Sql -Query 'EXEC sys.sp_help_change_event_stream_tables;'
        $tableOk = $tables -match 'SupportTicket'
        Add-Result 'SupportTicket is in the stream group' $tableOk $(if ($tableOk) { 'streaming' } else { 'not streaming' })

        $rows = Invoke-Sql -Query 'SELECT COUNT(*) FROM dbo.SupportTicket;'
        Add-Result 'Table is empty (clean opening state)' ($rows -eq '0') "$rows rows"
    }
}

Show-Section 'Data plane' $mark

# --- Function app ------------------------------------------------------------
$mark = $results.Count

$fn = Invoke-Az @('functionapp', 'show', '-g', $ResourceGroup, '-n', $FunctionApp) -AllowFailure
Add-Result 'Function app exists' ($null -ne $fn) $(if ($fn) { $fn.state } else { 'absent' })

$fnPrincipal = if ($fn) { $fn.identity.principalId } else { $null }
Add-Result 'Function has a system-assigned identity' (-not [string]::IsNullOrWhiteSpace($fnPrincipal)) $(if ($fnPrincipal) { $fnPrincipal } else { 'none' })

$srScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.SignalRService/SignalR/$SignalRName"
# Serverless mode needs the data-plane REST API (SignalR/hub/*) to broadcast.
# 'SignalR App Server' alone passes negotiate but 403s on every message, so
# check for the role that actually covers both.
$srRole = if ($fnPrincipal) {
    Invoke-Az @('role', 'assignment', 'list', '--assignee', $fnPrincipal, '--role', 'SignalR Service Owner', '--scope', $srScope) -AllowFailure
}
else { $null }
Add-Result 'Function identity can broadcast to SignalR' ($srRole -and @($srRole).Count -gt 0) $(if ($srRole -and @($srRole).Count -gt 0) { 'SignalR Service Owner' } else { 'missing (SignalR App Server is not enough in Serverless mode)' })

$appSettings = Invoke-Az @('functionapp', 'config', 'appsettings', 'list', '-g', $ResourceGroup, '-n', $FunctionApp) -AllowFailure
$settingNames = @($appSettings | ForEach-Object { $_.name })
$hasIdentityEh = $settingNames -contains 'EventHubConnection__fullyQualifiedNamespace'
$hasIdentitySr = $settingNames -contains 'AzureSignalRConnectionString__serviceUri'
Add-Result 'Event Hubs connection is identity-based' $hasIdentityEh $(if ($hasIdentityEh) { 'fullyQualifiedNamespace' } else { 'missing' })
Add-Result 'SignalR connection is identity-based' $hasIdentitySr $(if ($hasIdentitySr) { 'serviceUri' } else { 'missing' })

# The whole claim of this demo is that nothing anywhere holds a secret.
$secretLike = @($appSettings | Where-Object {
        $_.value -match 'SharedAccessKey|AccountKey=|AccessKey='
    } | ForEach-Object { $_.name })
Add-Result 'No key or connection string in app settings' ($secretLike.Count -eq 0) $(if ($secretLike.Count -eq 0) { 'clean' } else { $secretLike -join ', ' })

$cors = Invoke-Az @('functionapp', 'cors', 'show', '-g', $ResourceGroup, '-n', $FunctionApp) -AllowFailure
$corsOk = $cors -and ($cors.allowedOrigins -contains $WebOrigin)
Add-Result 'CORS allows the local page' $corsOk $(if ($cors) { ($cors.allowedOrigins -join ', ') } else { 'none' })

# Allow-listing the origin is not enough: the SignalR client negotiates with
# credentials, which needs Access-Control-Allow-Credentials: true.
$corsCredsOk = [bool]($cors -and $cors.supportCredentials)
Add-Result 'CORS allows credentialed requests' $corsCredsOk $(if ($corsCredsOk) { 'supportCredentials = true' } else { 'supportCredentials = false (SignalR negotiate will be blocked)' })

$negotiateOk = $false
$negotiateDetail = 'not reached'
try {
    $resp = Invoke-WebRequest -Uri "https://$FunctionApp.azurewebsites.net/api/negotiate" -Method Post -TimeoutSec 45 -SkipHttpErrorCheck
    $negotiateOk = $resp.StatusCode -eq 200
    $negotiateDetail = "HTTP $($resp.StatusCode)"
}
catch {
    $negotiateDetail = $_.Exception.Message.Split("`n")[0]
}
Add-Result 'negotiate endpoint responds' $negotiateOk $negotiateDetail

Show-Section 'Function app' $mark

# --- Summary -----------------------------------------------------------------
$pass = @($results | Where-Object Result -EQ 'PASS').Count
$total = $results.Count

Write-Host ''
if ($pass -eq $total) {
    Write-Host "$pass/$total PASS" -ForegroundColor Green
    Write-Host 'All checks passed. Demo is in its opening state.' -ForegroundColor Green
    exit 0
}
else {
    Write-Host "$pass/$total PASS" -ForegroundColor Red
    Write-Host ''
    $results | Where-Object Result -EQ 'FAIL' | ForEach-Object {
        Write-Host "    FAILED: $($_.Check) - $($_.Detail)" -ForegroundColor Red
    }
    exit 1
}
