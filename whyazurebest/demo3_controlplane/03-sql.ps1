<#
.SYNOPSIS
    Step 4 of 6. Creates the Entra-only logical server and the Hyperscale database.

.DESCRIPTION
    Runs from the presenter's laptop. Control plane only - no SQL connection.

    The server is created with --enable-ad-only-auth, so SQL authentication is
    off from birth. Per Microsoft Learn: "The server SQL administrator will be
    automatically created and the password will be set to a random password.
    Since SQL authentication connectivity is disabled with this server
    creation, the SQL administrator login won't be used."

    The Microsoft Entra admin is the VM's system-assigned managed identity.
    Learn allows a User, Group, or Application as the admin, and states that
    for a service principal you supply the Application ID. That single choice
    removes every credential from this demo: the VM connects with
    -A ActiveDirectoryMsi as a full admin, so there is no CREATE USER step, no
    access token to ferry from the laptop, and nothing that expires.

.NOTES
    THE 0.0.0.0 RULE IS INTENTIONAL.
    "AllowAllWindowsAzureIps" is what the portal checkbox "Allow Azure services
    and resources to access this server" creates. Learn: "your server allows
    communications from all resources inside the Azure boundary, regardless of
    whether they are part of your subscription." It is the anti-pattern this
    demo exists to kill, and Beat 4 depends on it still being present so the
    audience can see that it bought us nothing.
#>

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step 'Resolving the VM identity that will own this server'
$identity = Get-VmIdentity
Write-Ok "Application (client) ID: $($identity.AppId)"

Write-Step "Logical server '$ServerName'"
$server = Invoke-Az @('sql', 'server', 'show', '-g', $ResourceGroup, '-n', $ServerName) -AllowFailure
if ($server) {
    Write-Skip 'Already exists - not recreating'
}
else {
    Show-Command "az sql server create --enable-ad-only-auth --external-admin-principal-type Application --external-admin-name $VmName --external-admin-sid $($identity.AppId)"

    # Must be the application (client) ID, never the object ID. Learn: "Azure SQL
    # uses the application ID for service principals and managed identities, and
    # the object ID only for regular Entra users." The object ID is accepted at
    # create time and then fails at login, so there is no fallback worth having.
    $created = Invoke-Az @(
        'sql', 'server', 'create',
        '-g', $ResourceGroup,
        '-n', $ServerName,
        '--location', $Location,
        '--enable-ad-only-auth',
        '--external-admin-principal-type', 'Application',
        '--external-admin-name', $VmName,
        '--external-admin-sid', $identity.AppId,
        '--enable-public-network', 'true'
    ) -AllowFailure

    if (-not $created) {
        throw @"
Could not create the logical server with the VM identity as Entra admin using
the application ID ($($identity.AppId)).

Do NOT retry with the object ID ($($identity.PrincipalId)). Azure SQL matches
the token's appid claim, so the object ID produces a server that creates
cleanly and then fails every login with:
    Login failed for user '<token-identified principal>'
"@
    }
    Write-Ok 'Created using the application (client) ID'
}

Write-Step 'Confirming Microsoft Entra-only authentication'
$adOnly = & az sql server ad-only-auth get -g $ResourceGroup -n $ServerName `
    --query azureAdOnlyAuthentication -o tsv 2>&1
if ($LASTEXITCODE -ne 0) { throw "Could not read the Entra-only setting.`n$adOnly" }
$adOnly = ($adOnly | Out-String).Trim()
if ($adOnly -eq 'True') {
    Write-Ok 'azureAdOnlyAuthentication = True. No SQL login can connect to this server.'
}
else {
    throw "Expected azureAdOnlyAuthentication = True but found '$adOnly'."
}

Write-Step 'Current Microsoft Entra admin'
$admin = Invoke-Az @('sql', 'server', 'ad-admin', 'list', '-g', $ResourceGroup, '-s', $ServerName)
if ($admin) {
    foreach ($a in $admin) { Write-Ok "$($a.login)  sid=$($a.sid)" }
}
else {
    throw 'No Microsoft Entra admin is set. The VM will not be able to connect.'
}

Write-Step "Firewall rule '$AllowAzureRuleName' (0.0.0.0)"
$rule = Invoke-Az @(
    'sql', 'server', 'firewall-rule', 'show',
    '-g', $ResourceGroup, '-s', $ServerName, '-n', $AllowAzureRuleName
) -AllowFailure
if ($rule) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'sql', 'server', 'firewall-rule', 'create',
        '-g', $ResourceGroup,
        '-s', $ServerName,
        '-n', $AllowAzureRuleName,
        '--start-ip-address', '0.0.0.0',
        '--end-ip-address', '0.0.0.0'
    ) | Out-Null
    Write-Ok 'Created. Intentional. This is the anti-pattern the demo exists to kill.'
}

# Left empty on purpose. This demo proves reachability and identity, not data.
Write-Step "Hyperscale database '$DatabaseName' (serverless, Gen5, 2 vCore, empty)"
$db = Invoke-Az @('sql', 'db', 'show', '-g', $ResourceGroup, '-s', $ServerName, '-n', $DatabaseName) -AllowFailure
if ($db) {
    Write-Skip "Already exists - $($db.currentServiceObjectiveName)"
}
else {
    Show-Command "az sql db create --edition Hyperscale --family Gen5 --capacity 2 --compute-model Serverless"
    Invoke-Az @(
        'sql', 'db', 'create',
        '-g', $ResourceGroup,
        '-s', $ServerName,
        '-n', $DatabaseName,
        '--edition', 'Hyperscale',
        '--family', 'Gen5',
        '--capacity', '2',
        '--compute-model', 'Serverless',
        '--backup-storage-redundancy', 'Local'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Host ''
Write-Ok 'Step 4 complete. Next: .\04-vm-prereqs.ps1'
