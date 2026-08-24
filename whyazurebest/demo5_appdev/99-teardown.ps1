# Full cleanup. Deletes the whole resource group.
#
# Demo 5 lives in its own resource group precisely so teardown is one command
# and cannot touch demo 1 or demo 3.

param([switch]$Force)

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

$rg = Invoke-Az @('group', 'show', '-n', $ResourceGroup) -AllowFailure
if (-not $rg) {
    Write-Skip "Resource group '$ResourceGroup' does not exist. Nothing to do."
    return
}

Write-Step "About to DELETE the resource group '$ResourceGroup'"
$contents = Invoke-Az @('resource', 'list', '-g', $ResourceGroup, '--query', '[].{name:name,type:type}') -AllowFailure
foreach ($r in $contents) { Write-Warn "$($r.type)  $($r.name)" }

if (-not $Force) {
    Write-Host ''
    $answer = Read-Host "  Type the resource group name to confirm"
    if ($answer -ne $ResourceGroup) {
        Write-Skip 'Cancelled.'
        return
    }
}

Write-Step 'Deleting'
Invoke-Az @('group', 'delete', '-n', $ResourceGroup, '--yes', '--no-wait') | Out-Null
Write-Ok 'Delete started (running in the background).'
Write-Skip "Check with: az group show -n $ResourceGroup"
