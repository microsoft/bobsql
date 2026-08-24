# Step 3 - Create the table, then turn on Change Event Streaming.
#
# Order matters. The primary key has to exist before CES is enabled, because you
# cannot add or drop one while a table is being streamed.

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step 'Checking sqlsim'
if (-not (Test-Path $script:SqlSim)) {
    throw "sqlsim not found at $($script:SqlSim). Build it from C:\bwsql\sqlsimtools\sqlsim."
}
Write-Ok $script:SqlSim

Write-Step 'Firewall rule for this laptop'
Set-PresenterFirewall
Write-Ok 'Server reachable'

Write-Step "Waking the database (serverless, so the first connection may take ~30s)"
$who = Invoke-Sql -Query 'SELECT SUSER_SNAME() AS ConnectedAs;'
Write-Ok $who

Write-Step 'Creating dbo.SupportTicket'
$out = Invoke-SqlFile -Path (Join-Path $SqlDir '01-schema.sql')
$out -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Ok $_.Trim() }

Write-Step 'Enabling Change Event Streaming'
Write-Skip "Destination: $EventHubFqdn`:9093/$EventHubName"

# The master key needs a password, but nothing ever needs it again: on Azure SQL
# the master key is also protected by the service master key. Generate one,
# use it once, drop it on the floor.
$dmkPassword = [System.Guid]::NewGuid().ToString('N') + 'Aa1!'

$out = Invoke-SqlFile -Path (Join-Path $SqlDir '02-enable-ces.sql') -Variables @{
    DmkPassword         = $dmkPassword
    CredentialName      = $CredentialName
    StreamGroupName     = $StreamGroupName
    DestinationLocation = "$EventHubFqdn`:9093/$EventHubName"
    TableName           = $TableName
}
$dmkPassword = $null

Write-Host $out

Write-Step 'Done'
Write-Ok "dbo.SupportTicket is streaming to $EventHubName"
