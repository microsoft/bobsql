#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Operation,
    [Parameter(Mandatory)][string] $InputFile
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'Studio.Engine.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Studio.Migration.psm1') -Force -DisableNameChecking
try {
    if ($Operation -cnotin @('Containers','Databases','Preflight','Tenants','Subscriptions','Locations','Groups','Servers','Identity','Migrate')) {
        Stop-StudioOperation 'InvalidOperation' 'The requested operation is not allowlisted.'
    }
    Assert-StudioProtectedFile $InputFile
    try { $config = Get-Content -LiteralPath $InputFile -Raw | ConvertFrom-Json -AsHashtable -Depth 10 }
    catch { Stop-StudioOperation 'InvalidRequest' 'The protected request file must contain valid JSON.' }
    if ($config -isnot [System.Collections.IDictionary]) { Stop-StudioOperation 'InvalidRequest' 'The request must be a JSON object.' }
    Assert-StudioConfiguration $config $Operation
    $result = switch -CaseSensitive ($Operation) {
        'Containers' { @(Get-StudioSource) }
        'Databases' {
            $source = Get-StudioSource -Credential
            $connection = Open-StudioSourceConnection $source 'master'
            try {
                $databases = Invoke-StudioQuery $connection "SELECT name FROM sys.databases WHERE name NOT IN (N'master', N'tempdb', N'model', N'msdb') AND state = 0 ORDER BY name;"
                $list = @(
                    foreach ($row in $databases.Rows) {
                        $dbConnection = Open-StudioSourceConnection $source $row.name
                        try {
                            $counts = Invoke-StudioQuery $dbConnection @'
SELECT COUNT(*) AS TableCount FROM sys.tables WHERE is_ms_shipped = 0;
'@
                            $entry = @{name=[string]$row.name;tableCount=[int]$counts.Rows[0].TableCount}
                            # Separate maintained query keeps optional case discovery independent of result-set loading.
                            $exists = Invoke-StudioQuery $dbConnection "SELECT CASE WHEN OBJECT_ID(N'dbo.Cases', N'U') IS NOT NULL THEN 1 ELSE 0 END AS HasCases;"
                            if ($exists.Rows[0].HasCases -eq 1) {
                                $cases = Invoke-StudioQuery $dbConnection 'SELECT COUNT_BIG(*) AS CaseCount FROM dbo.Cases;'
                                $entry.caseCount = [long]$cases.Rows[0].CaseCount
                            }
                            $entry
                        } finally { $dbConnection.Dispose() }
                    }
                )
                @{endpoint=$source.endpoint;databases=$list}
            } finally { $connection.Dispose(); $source.password.Dispose(); $source=$null }
        }
        'Preflight' { Get-StudioPreflight $config }
        'Tenants' {
            $accounts = @(Invoke-StudioAz @('account','list','--all'))
            @($accounts | Group-Object tenantId | ForEach-Object {
                $name = $_.Name
                $display = $_.Group[0].PSObject.Properties['tenantDisplayName']
                if ($display -and $display.Value) { $name = $display.Value }
                @{id=$_.Name;name=$name}
            })
        }
        'Subscriptions' { @(Get-StudioSubscriptions $config) }
        'Identity' { Get-StudioIdentity $config }
        'Locations' {
            Assert-StudioAzureContext $config
            $response = Invoke-StudioAz @('rest','--method','get','--url',"https://management.azure.com/subscriptions/$($config.subscriptionId)/locations?api-version=2022-12-01")
            @($response.value |
                ForEach-Object { @{id=$_.name;name=$_.displayName} })
        }
        'Groups' {
            Assert-StudioAzureContext $config
            @(Invoke-StudioAz @('group','list','--subscription',$config.subscriptionId) |
                ForEach-Object { @{id=$_.id;name=$_.name;region=$_.location} })
        }
        'Servers' {
            Assert-StudioAzureContext $config
            if (-not $config.Contains('resourceGroup')) { Stop-StudioOperation 'GroupRequired' 'Select a resource group first.' }
            @(Invoke-StudioAz @('sql','server','list','--subscription',$config.subscriptionId,'--resource-group',$config.resourceGroup) |
                ForEach-Object { @{id=$_.id;name=$_.name;region=$_.location;fullyQualifiedDomainName=$_.fullyQualifiedDomainName} })
        }
        'Migrate' { Invoke-StudioMigration $config $InputFile }
    }
    if ($Operation -in @('Containers','Tenants','Subscriptions','Locations','Groups','Servers')) {
        $result = if ($null -eq $result) { ,@() } else { ,@($result) }
    }
    # -InputObject preserves singleton and empty discovery arrays.
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $result -Depth 30 -Compress))
    exit 0
} catch {
    $safe = Get-StudioSafeError $_
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject @{safeError=$safe.message;code=$safe.code;success=$false;verified=$false} -Depth 5 -Compress))
    exit 1
}
