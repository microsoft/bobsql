<#
.SYNOPSIS
    Step 6 of 6. Pre-flight. Asserts the demo is sitting in its Beat 1 state.

.DESCRIPTION
    Runs from the presenter's laptop. Every check that touches the data plane
    executes inside the VM via 'az vm run-command', so this works from
    conference wifi.

    Run it after setup, after reset-demo.ps1, and on the morning of the talk.
    Exit code 0 means the demo will run.

.NOTES
    The point of this script is to fail LOUDLY here rather than quietly on
    stage. In particular it fails if the private endpoint or the DNS VNet link
    already exist, because those are Beats 2 and 5.
#>

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

Write-Step 'Control plane'

$server = Invoke-Az @('sql', 'server', 'show', '-g', $ResourceGroup, '-n', $ServerName) -AllowFailure
if (-not $server) {
    Add-Result 'Logical server exists' $false "$ServerName not found"
}
else {
    Add-Result 'Logical server exists' $true $ServerName
    Add-Result 'publicNetworkAccess = Enabled' ($server.publicNetworkAccess -eq 'Enabled') $server.publicNetworkAccess
}

$adOnly = (& az sql server ad-only-auth get -g $ResourceGroup -n $ServerName `
    --query azureAdOnlyAuthentication -o tsv 2>&1 | Out-String).Trim()
Add-Result 'Entra-only authentication is ON' ($adOnly -eq 'True') "azureAdOnlyAuthentication = $adOnly"

$identity = $null
try { $identity = Get-VmIdentity } catch { }
$admins = Invoke-Az @('sql', 'server', 'ad-admin', 'list', '-g', $ResourceGroup, '-s', $ServerName) -AllowFailure
if ($admins -and $identity) {
    $sids = @($admins | ForEach-Object { $_.sid })
    # Application ID only. The object ID would pass a loose check and fail every login.
    $match = $sids -contains $identity.AppId
    Add-Result 'Entra admin is the VM managed identity' $match "$($admins[0].login) sid=$($admins[0].sid)"
}
else {
    Add-Result 'Entra admin is the VM managed identity' $false 'Could not read the admin or the VM identity'
}

$azureRule = Invoke-Az @(
    'sql', 'server', 'firewall-rule', 'show',
    '-g', $ResourceGroup, '-s', $ServerName, '-n', $AllowAzureRuleName
) -AllowFailure
Add-Result "Firewall rule '$AllowAzureRuleName' present" ([bool]$azureRule) $(if ($azureRule) { '0.0.0.0 - the deliberate anti-pattern' } else { 'missing' })

$db = Invoke-Az @('sql', 'db', 'show', '-g', $ResourceGroup, '-s', $ServerName, '-n', $DatabaseName) -AllowFailure
Add-Result 'Hyperscale database exists' ([bool]$db) $(if ($db) { $db.currentServiceObjectiveName } else { "$DatabaseName not found" })

Write-Step 'Beat 2 and Beat 5 must NOT have happened yet'

$pe = Invoke-Az @('network', 'private-endpoint', 'show', '-g', $ResourceGroup, '-n', $PeName) -AllowFailure
Add-Result 'Private endpoint is ABSENT' (-not $pe) $(if ($pe) { "$PeName exists - run reset-demo.ps1" } else { 'absent' })

$zone = Invoke-Az @('network', 'private-dns', 'zone', 'show', '-g', $ResourceGroup, '-n', $PrivateDnsZone) -AllowFailure
Add-Result 'Private DNS zone is ABSENT' (-not $zone) $(if ($zone) { "$PrivateDnsZone exists - run reset-demo.ps1" } else { 'absent' })

if ($zone) {
    $link = Invoke-Az @(
        'network', 'private-dns', 'link', 'vnet', 'show',
        '-g', $ResourceGroup, '-z', $PrivateDnsZone, '-n', $DnsLinkName
    ) -AllowFailure
    Add-Result 'DNS VNet link is ABSENT' (-not $link) $(if ($link) { "$DnsLinkName exists - run reset-demo.ps1" } else { 'absent' })
}

Write-Step 'Access to the VM'

$vm = Invoke-Az @('vm', 'show', '-g', $ResourceGroup, '-n', $VmName, '-d') -AllowFailure
Add-Result 'VM is running' ($vm -and $vm.powerState -eq 'VM running') $(if ($vm) { $vm.powerState } else { "$VmName not found" })

$rdpRule = Invoke-Az @(
    'network', 'nsg', 'rule', 'show',
    '-g', $ResourceGroup, '--nsg-name', $NsgName, '--name', $RdpRuleName
) -AllowFailure
if ($rdpRule) {
    $myIp = Get-MyPublicIp
    $src = $rdpRule.sourceAddressPrefix
    Add-Result 'RDP rule points at this machine' ($src -eq "$myIp/32") "rule=$src  me=$myIp/32  (run .\allow-me.ps1 to fix)"
}
else {
    Add-Result 'RDP rule points at this machine' $false "'$RdpRuleName' not found - run .\allow-me.ps1"
}

Write-Step 'Data plane, from inside the VM'

$vmState = $null
try {
    $vmState = Invoke-VmScript @"
if (Get-OdbcDriver -Name 'ODBC Driver 18 for SQL Server' -ErrorAction SilentlyContinue) { 'ODBC=PRESENT' } else { 'ODBC=MISSING' }
if (Test-Path '$VmSqlSim') { 'SQLSIM=PRESENT' } else { 'SQLSIM=MISSING' }
if (Test-Path '$VmKitDir\query.ps1') { 'KIT=PRESENT' } else { 'KIT=MISSING' }
Clear-DnsClientCache
`$a = (Resolve-DnsName -Name '$ServerFqdn' -Type A -ErrorAction SilentlyContinue | Where-Object IPAddress | Select-Object -First 1).IPAddress
"DNS=`$a"
`$t = Test-NetConnection -ComputerName '$ServerFqdn' -Port 1433 -WarningAction SilentlyContinue
"TCP1433=`$(`$t.TcpTestSucceeded)"
"@
}
catch {
    Add-Result 'VM run-command reachable' $false $_.Exception.Message
}

if ($vmState) {
    Add-Result 'VM run-command reachable' $true 'ok'
    Add-Result 'ODBC Driver 18 installed on the VM' ($vmState -match 'ODBC=PRESENT') $(if ($vmState -match 'ODBC=PRESENT') { 'present' } else { 'run .\04-vm-prereqs.ps1' })
    Add-Result 'sqlsim.exe on the VM' ($vmState -match 'SQLSIM=PRESENT') $(if ($vmState -match 'SQLSIM=PRESENT') { $VmSqlSim } else { "copy it from $SqlSimLocal" })
    Add-Result 'Demo kit on the VM' ($vmState -match 'KIT=PRESENT') $(if ($vmState -match 'KIT=PRESENT') { "$VmKitDir\query.ps1" } else { "copy the vmkit folder to $VmKitDir" })

    $dnsIp = if ($vmState -match 'DNS=([\d\.]+)') { $Matches[1] } else { '' }
    Add-Result 'VM resolves a PUBLIC IP' ($dnsIp -and $dnsIp -notmatch '^10\.42\.') $(if ($dnsIp) { $dnsIp } else { 'no A record' })
    Add-Result 'VM can reach port 1433' ($vmState -match 'TCP1433=True') $(if ($vmState -match 'TCP1433=True') { 'open' } else { 'blocked' })
}

if ($vmState -match 'SQLSIM=PRESENT') {
    Write-Step 'Running the demo query as the VM managed identity'
    $q = Invoke-VmScript "& '$VmSqlSim' -S '$ServerFqdn' -d '$DatabaseName' -A ActiveDirectoryMsi -Q `"$DemoQuery`" -l 30 2>&1 | Out-String"
    $ok = ($q -notmatch 'Msg \d+|Login failed|Cannot open|denied|not accessible') -and ($q -match 'ConnectedAs')
    Add-Result 'VM queries the database via managed identity' $ok $(if ($ok) { 'rows returned' } else { ($q -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 2) -join ' | ' })
}

Write-Host ''
$results | Format-Table -AutoSize @{ Label = 'Result'; Expression = { $_.Result } },
    @{ Label = 'Check'; Expression = { $_.Check } },
    @{ Label = 'Detail'; Expression = { $_.Detail } } | Out-String | Write-Host

$failed = @($results | Where-Object { $_.Result -eq 'FAIL' })
if ($failed.Count -gt 0) {
    Write-Fail "$($failed.Count) check(s) failed. Fix these before you rehearse."
    exit 1
}

Write-Ok 'All checks passed. Demo is in its Beat 1 state.'
