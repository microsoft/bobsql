[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
$exists = Invoke-Az @('group', 'exists', '--name', $ResourceGroup, '--output', 'tsv') -Raw
if ($exists -ne 'true') {
    Write-Skip "$ResourceGroup does not exist"
    return
}

if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Delete the resource group and every contained resource')) {
    Invoke-Az @('group', 'delete', '--name', $ResourceGroup, '--yes', '--no-wait', '--output', 'none') | Out-Null
    Write-Host "Deletion started for $ResourceGroup." -ForegroundColor Yellow
}
