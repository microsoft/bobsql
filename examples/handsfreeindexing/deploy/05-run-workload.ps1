$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
Invoke-DemoSqlFile -Path (Join-Path $PSScriptRoot '..\01-workload.sql') -TimeoutSeconds 1200

Write-Host 'One 15-minute missing-index workload interval completed.' -ForegroundColor Green