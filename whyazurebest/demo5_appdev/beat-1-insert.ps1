# The live beat. One INSERT. Nothing else.
#
# Everything downstream is asleep when this runs: the database is serverless and
# may be paused, the function app is scaled to zero. This row wakes all of it.

param(
    [string]$CustomerName = 'Contoso Manufacturing',
    [ValidateRange(1, 4)][int]$Severity = 1,
    [string]$Subject = 'Order pipeline stalled after failover',
    [string]$Body = 'Orders stopped flowing at 09:14 UTC. Retries are timing out against the primary. Customer is asking for an ETA.'
)

. "$PSScriptRoot\00-config.ps1"

$sql = @"
INSERT INTO dbo.SupportTicket (CustomerName, Severity, Subject, Body)
VALUES (N'$($CustomerName -replace "'", "''")', $Severity,
        N'$($Subject -replace "'", "''")', N'$($Body -replace "'", "''")');

SELECT SCOPE_IDENTITY() AS TicketId;
"@

Write-Beat 'INSERT one support ticket'
Show-Command 'INSERT INTO dbo.SupportTicket (CustomerName, Severity, Subject, Body) VALUES (...)'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ticketId = Invoke-Sql -Query $sql
$sw.Stop()

Write-Host ''
Write-Ok "Ticket $ticketId committed in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
Write-Host ''
Write-Skip 'The database published a change event to Event Hubs.'
Write-Skip 'The function app woke up, read it, and pushed it to SignalR.'
Write-Skip 'Watch the browser.'
