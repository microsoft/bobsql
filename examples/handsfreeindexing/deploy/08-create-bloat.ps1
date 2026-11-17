$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
Invoke-DemoSqlFile -Path (Join-Path $PSScriptRoot '..\03-create-bloat.sql') -TimeoutSeconds 3600

Write-Host 'Insert/delete bloat workload completed.' -ForegroundColor Green