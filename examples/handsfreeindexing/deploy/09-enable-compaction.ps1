$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
Invoke-DemoSqlFile -Path (Join-Path $PSScriptRoot '..\04-enable-compaction.sql') -TimeoutSeconds 3600

Write-Host 'Automatic Index Compaction enabled and eligibility workload completed.' -ForegroundColor Green