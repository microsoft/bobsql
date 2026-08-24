# Orchestrator. Runs steps 1-5 in order. Re-runnable: every step is idempotent.
#
#   .\setup-all.ps1              # everything
#   .\setup-all.ps1 -From 4      # just redeploy the function and verify
#   .\setup-all.ps1 -From 3 -To 3

param(
    [ValidateRange(1, 5)][int]$From = 1,
    [ValidateRange(1, 5)][int]$To = 5
)

$ErrorActionPreference = 'Stop'

$steps = @(
    @{ N = 1; Name = 'Messaging (Event Hubs + SignalR)'; Script = '01-messaging.ps1' }
    @{ N = 2; Name = 'Azure SQL (server + Hyperscale DB)'; Script = '02-sql.ps1' }
    @{ N = 3; Name = 'Schema + Change Event Streaming'; Script = '03-schema.ps1' }
    @{ N = 4; Name = 'Function app'; Script = '04-function.ps1' }
    @{ N = 5; Name = 'Verify'; Script = '05-verify.ps1' }
)

. "$PSScriptRoot\00-config.ps1"

foreach ($step in $steps) {
    if ($step.N -lt $From -or $step.N -gt $To) { continue }

    Write-Beat "STEP $($step.N)  $($step.Name)"
    & (Join-Path $PSScriptRoot $step.Script)
    if ($LASTEXITCODE -ne 0 -and $step.N -eq 5) {
        Write-Fail 'Verification failed. Fix the FAILs above before presenting.'
        exit 1
    }
}

Write-Beat 'Setup complete'
Write-Ok "Start the page : .\serve-page.ps1"
Write-Ok "Fire an event  : .\beat-1-insert.ps1"
