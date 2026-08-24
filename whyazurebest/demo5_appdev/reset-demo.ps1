# Rewind to the opening state: empty the ticket table and refresh the firewall
# rule for wherever the presenter is today.
#
# CES stays enabled. Deleting rows does emit delete events, so drain them before
# going on stage rather than during.

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step 'Firewall rule for this laptop'
Set-PresenterFirewall
Write-Ok 'Server reachable as the Entra admin'

Write-Step 'Emptying dbo.SupportTicket'
# TRUNCATE TABLE is blocked on a table enabled for CES.
$before = Invoke-Sql -Query 'SELECT COUNT(*) FROM dbo.SupportTicket;'
Invoke-Sql -Query 'DELETE FROM dbo.SupportTicket;' | Out-Null
Invoke-Sql -Query 'DBCC CHECKIDENT (''dbo.SupportTicket'', RESEED, 0) WITH NO_INFOMSGS;' | Out-Null
Write-Ok "Deleted $before row(s), identity reseeded"

Write-Step 'Letting the delete events drain'
Start-Sleep -Seconds 20
Write-Ok 'Done'

Write-Step 'Ready'
Write-Ok 'Run .\05-verify.ps1 to confirm, then .\serve-page.ps1'
