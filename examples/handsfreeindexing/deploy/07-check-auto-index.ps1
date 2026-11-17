$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
Invoke-DemoSqlFile -Path (Join-Path $PSScriptRoot '..\02-check-auto-index.sql') -TimeoutSeconds 300