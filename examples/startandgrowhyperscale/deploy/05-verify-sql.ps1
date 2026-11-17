[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null

$server = Invoke-Az @('sql', 'server', 'show', '--resource-group', $ResourceGroup, '--name', $SqlServerName, '--output', 'json')
$adOnly = Invoke-Az @('sql', 'server', 'ad-only-auth', 'get', '--resource-group', $ResourceGroup, '--name', $SqlServerName, '--output', 'json')
Write-Step 'Logical server'
[pscustomobject]@{
    Server         = $server.name
    Fqdn           = $server.fullyQualifiedDomainName
    Region         = $server.location
    EntraOnly      = $adOnly.azureAdOnlyAuthentication
    EntraAdmin     = $server.administrators.login
    PublicNetwork  = $server.publicNetworkAccess
    MinTls         = $server.minimalTlsVersion
    ResourceId     = $server.id
} | Format-List

Write-Step 'Databases'
$databases = @(Invoke-Az @('sql', 'db', 'list', '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--output', 'json') |
    Where-Object name -ne 'master')
$databases |
    ForEach-Object {
        [pscustomobject]@{
            Database      = $_.name
            Slo           = $_.currentServiceObjectiveName
            Compute       = if ($_.kind -match 'serverless') { 'Serverless' } else { 'Provisioned' }
            MinVCores     = $_.minCapacity
            AutoPauseMin  = $_.autoPauseDelay
            Pool          = $_.elasticPoolName
            Status        = $_.status
            Backup        = $_.requestedBackupStorageRedundancy
            ZoneRedundant = $_.zoneRedundant
        }
    } | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

Write-Step 'Elastic pools'
Invoke-Az @('sql', 'elastic-pool', 'list', '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--output', 'json') |
    ForEach-Object {
        [pscustomobject]@{
            Pool          = $_.name
            Edition       = $_.edition
            VCores        = $_.sku.capacity
            MinPerDatabase = $_.perDatabaseSettings.minCapacity
            MaxPerDatabase = $_.perDatabaseSettings.maxCapacity
            State         = $_.state
            ZoneRedundant = $_.zoneRedundant
            Databases     = @($databases | Where-Object elasticPoolName -eq $_.name).Count
        }
    } | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
