[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,
    [string]$Location = 'westus3',
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$')]
    [string]$SqlServerName,
    [ValidateSet('CaldovaRegionalCare')]
    [string]$DatabaseName = 'CaldovaRegionalCare',
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$')]
    [string]$FoundryResourceName,
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$')]
    [string]$ModelDeployment = 'gpt-4.1-mini',
    [int]$ModelCapacity = 1,
    [string]$ClientIp,
    [switch]$UseAzureServicesFirewall,
    [switch]$TestFoundry
)

$ErrorActionPreference = 'Stop'
$sharedDatabasePath = Join-Path $PSScriptRoot '..\database'
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
$serverFqdn = "$SqlServerName.database.windows.net"
$foundryHost = "$FoundryResourceName.services.ai.azure.com"
$firewallRuleName = "CaldovaBuild-$PID"
$azureServicesFirewallRuleName = "CaldovaBuildAzure-$PID"
$firewallCreated = $false
$azureServicesFirewallCreated = $false

if (-not $sqlcmd -or -not (& $sqlcmd.Source --version 2>$null)) {
    throw 'This deployment requires go-sqlcmd. Install it from https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install and reopen PowerShell.'
}

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return $output
}

function Invoke-CaldovaSql {
    param(
        [string]$ScriptPath,
        [string]$Query,
        [switch]$Capture
    )

    $arguments = @('-S', $serverFqdn, '-d', $DatabaseName,
        '--authentication-method', 'ActiveDirectoryDefault', '-N', 's',
        '-l', '30', '-t', '230', '-b')
    if ($ScriptPath) {
        $arguments += @('-i', $ScriptPath, '-v',
            "FoundryResourceName=$FoundryResourceName", "ModelDeployment=$ModelDeployment")
    }
    else {
        $arguments += @('-Q', $Query)
    }

    if ($Capture) {
        $arguments += @('-h', '-1', '-W')
        $output = & $sqlcmd.Source @arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Azure SQL command failed:`n$($output -join [Environment]::NewLine)"
        }
        return $output
    }

    & $sqlcmd.Source @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure SQL command failed."
    }
}

Write-Host 'Caldova Regional Care: Hyperscale + Microsoft Foundry' -ForegroundColor Cyan
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

$account = Invoke-Az @('account', 'show', '--query', '{id:id,user:user.name}', '--output', 'json') |
    ConvertFrom-Json
$signedInUser = Invoke-Az @('ad', 'signed-in-user', 'show',
    '--query', '{displayName:displayName,id:id}', '--output', 'json') | ConvertFrom-Json
Write-Host "Subscription: $($account.id)" -ForegroundColor DarkGray
Write-Host "Identity:     $($account.user)" -ForegroundColor DarkGray

$resourceGroupExists = Invoke-Az @('group', 'exists', '--name', $ResourceGroup, '--output', 'tsv')
if ($resourceGroupExists -notcontains 'true') {
    Invoke-Az @('group', 'create', '--name', $ResourceGroup, '--location', $Location,
        '--tags', 'workload=CaldovaRegionalCare', 'event=sqlconeurope2026', '--output', 'none') | Out-Null
}

$server = & az sql server show --name $SqlServerName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    $server = Invoke-Az @('sql', 'server', 'create', '--name', $SqlServerName,
        '--resource-group', $ResourceGroup, '--location', $Location,
        '--enable-ad-only-auth', '--external-admin-principal-type', 'User',
        '--external-admin-name', $signedInUser.displayName,
        '--external-admin-sid', $signedInUser.id, '--assign-identity',
        '--minimal-tls-version', '1.2', '--tags', 'workload=CaldovaRegionalCare',
        'event=sqlconeurope2026', '--output', 'json')
}
$server = $server | ConvertFrom-Json
if (-not $server.identity.principalId) {
    $server = Invoke-Az @('sql', 'server', 'update', '--name', $SqlServerName,
        '--resource-group', $ResourceGroup, '--assign-identity', '--output', 'json') |
        ConvertFrom-Json
}

$database = & az sql db show --resource-group $ResourceGroup --server $SqlServerName `
    --name $DatabaseName --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    $database = Invoke-Az @('sql', 'db', 'create', '--resource-group', $ResourceGroup,
        '--server', $SqlServerName, '--name', $DatabaseName, '--edition', 'Hyperscale',
        '--compute-model', 'Provisioned', '--family', 'Gen5', '--capacity', '8',
        '--backup-storage-redundancy', 'Local', '--zone-redundant', 'false',
        '--tags', 'workload=CaldovaRegionalCare', 'event=sqlconeurope2026', '--output', 'json')
}
$database = $database | ConvertFrom-Json
if ($database.sku.tier -ne 'Hyperscale' -or $database.sku.capacity -ne 8) {
    throw "$DatabaseName exists but is not an 8-vCore Hyperscale database."
}

$foundry = & az cognitiveservices account show --name $FoundryResourceName `
    --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    $foundry = Invoke-Az @('cognitiveservices', 'account', 'create',
        '--name', $FoundryResourceName, '--resource-group', $ResourceGroup,
        '--location', $Location, '--kind', 'AIServices', '--sku', 'S0',
        '--custom-domain', $FoundryResourceName, '--yes', '--output', 'json')
}
$foundry = $foundry | ConvertFrom-Json

$null = & az cognitiveservices account deployment show --name $FoundryResourceName `
    --resource-group $ResourceGroup --deployment-name $ModelDeployment --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Az @('cognitiveservices', 'account', 'deployment', 'create',
        '--name', $FoundryResourceName, '--resource-group', $ResourceGroup,
        '--deployment-name', $ModelDeployment, '--model-name', 'gpt-4.1-mini',
        '--model-version', '2025-04-14', '--model-format', 'OpenAI',
        '--sku-name', 'GlobalStandard', '--sku-capacity', $ModelCapacity.ToString(),
        '--output', 'none') | Out-Null
}

$foundryId = $foundry.id
$serverPrincipalId = $server.identity.principalId
$roleAssignment = & az role assignment list --assignee-object-id $serverPrincipalId `
    --scope $foundryId --role 'Cognitive Services OpenAI User' --query '[0].id' `
    --output tsv 2>$null
if (-not $roleAssignment) {
    Invoke-Az @('role', 'assignment', 'create', '--assignee-object-id', $serverPrincipalId,
        '--assignee-principal-type', 'ServicePrincipal', '--scope', $foundryId,
        '--role', 'Cognitive Services OpenAI User', '--output', 'none') | Out-Null
}

try {
    if (-not $ClientIp) {
        $ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
    }
    Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '--resource-group', $ResourceGroup,
        '--server', $SqlServerName, '--name', $firewallRuleName,
        '--start-ip-address', $ClientIp, '--end-ip-address', $ClientIp,
        '--output', 'none') | Out-Null
    $firewallCreated = $true
    if ($UseAzureServicesFirewall) {
        Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '--resource-group', $ResourceGroup,
            '--server', $SqlServerName, '--name', $azureServicesFirewallRuleName,
            '--start-ip-address', '0.0.0.0', '--end-ip-address', '0.0.0.0',
            '--output', 'none') | Out-Null
        $azureServicesFirewallCreated = $true
    }

    $schemaState = Invoke-CaldovaSql -Query @'
IF OBJECT_ID(N'ops.Facility', N'U') IS NULL
    SELECT 'CALDOVA_SCHEMA_MISSING' AS SchemaState;
ELSE
    SELECT 'CALDOVA_SCHEMA_PRESENT' AS SchemaState;
'@ -Capture

    if ($schemaState -match 'CALDOVA_SCHEMA_MISSING') {
        foreach ($name in '01-schema.sql', '02-seed.sql') {
            Write-Host "Running shared $name..." -ForegroundColor Cyan
            Invoke-CaldovaSql -ScriptPath (Join-Path $sharedDatabasePath $name)
        }
    }

    foreach ($name in '01b-ledger.sql', '03-programmability.sql', 'test-packet.sql') {
        Write-Host "Running shared $name..." -ForegroundColor Cyan
        Invoke-CaldovaSql -ScriptPath (Join-Path $sharedDatabasePath $name)
    }

    $masterKeyBytes = [byte[]]::new(48)
    [Security.Cryptography.RandomNumberGenerator]::Fill($masterKeyBytes)
    $masterKeyPassword = [Convert]::ToBase64String($masterKeyBytes) + '!aA1'
    $escapedMasterKeyPassword = $masterKeyPassword.Replace("'", "''")
    Invoke-CaldovaSql -Query @"
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE [name] = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$escapedMasterKeyPassword';
"@

    Invoke-CaldovaSql -ScriptPath `
        (Join-Path $PSScriptRoot 'database\05-configure-foundry-model.sql')

    Write-Host 'Running shared 07-rag.sql...' -ForegroundColor Cyan
    Invoke-CaldovaSql -ScriptPath (Join-Path $sharedDatabasePath '07-rag.sql')
    Invoke-CaldovaSql -ScriptPath (Join-Path $PSScriptRoot 'database\Verify.sql')

    if ($TestFoundry) {
        Invoke-CaldovaSql -ScriptPath (Join-Path $sharedDatabasePath 'test-foundry-ai.sql')
    }
}
finally {
    $masterKeyPassword = $null
    $masterKeyBytes = $null
    if ($firewallCreated) {
        & az sql server firewall-rule delete --resource-group $ResourceGroup `
            --server $SqlServerName --name $firewallRuleName --output none 2>$null
    }
    if ($azureServicesFirewallCreated) {
        & az sql server firewall-rule delete --resource-group $ResourceGroup `
            --server $SqlServerName --name $azureServicesFirewallRuleName --output none 2>$null
    }
}

Write-Host ''
Write-Host 'Caldova Hyperscale + Microsoft Foundry deployment passed.' -ForegroundColor Green
Write-Host "SQL:     $serverFqdn / $DatabaseName ($($database.currentServiceObjectiveName))"
Write-Host "Foundry: https://$foundryHost/openai / $ModelDeployment"
if (-not $TestFoundry) {
    Write-Host 'Live model invocation was not run. Use -TestFoundry when ready.' -ForegroundColor Yellow
}