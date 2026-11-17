[CmdletBinding()]
param(
    [string]$Server,
    [string]$SourceDatabase = 'SalesDB',
    [string]$TargetDatabase = 'InventoryDB'
)

# Read-only smoke test for the native cross-database query preview, using the test objects from
# docs\crossdb-private-preview.md (dbo.Orders in the source, dbo.Inventory and dbo.GetInventory in the target).
# Exit code 0 = cross-database queries work; 1 = they do not.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\00-config.ps1"
Import-Module SqlServer -ErrorAction Stop
if (-not $Server) { $Server = $SqlServerFqdn }

$token = (Invoke-Az @('account', 'get-access-token', '--subscription', $SubscriptionId,
    '--resource', 'https://database.windows.net/', '--output', 'json')).accessToken

$checks = [ordered]@{
    'Identity'                     = 'SELECT ORIGINAL_LOGIN() AS login_name, USER_NAME() AS database_user, DB_NAME() AS connected_database;'
    'Read another database'        = "SELECT TOP (10) ProductId, Quantity FROM [$TargetDatabase].[dbo].[Inventory];"
    'Join local and remote tables' = "SELECT o.OrderId, o.ProductId, i.Quantity FROM [dbo].[Orders] AS o JOIN [$TargetDatabase].[dbo].[Inventory] AS i ON i.ProductId = o.ProductId;"
    'Call a remote procedure'      = "EXEC [$TargetDatabase].[dbo].[GetInventory] @ProductId = 42;"
}

Write-Step "Cross-database smoke test: $Server, from $SourceDatabase to $TargetDatabase ($((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC)"
$failed = 0
foreach ($name in $checks.Keys) {
    try {
        $rows = @(Invoke-Sqlcmd -ServerInstance $Server -Database $SourceDatabase -AccessToken $token -Encrypt Mandatory `
            -ConnectionTimeout 60 -QueryTimeout 60 -Query $checks[$name] -ErrorAction Stop)
        Write-Ok "PASS  $name ($($rows.Count) rows)"
        if ($name -eq 'Identity') { $rows | Format-Table -AutoSize | Out-String | Write-Host }
    }
    catch {
        $failed++
        Write-Host "    FAIL  $name" -ForegroundColor Red
        Write-Host "          $($checks[$name])"
        Write-Host "          $($_.Exception.Message.Trim())" -ForegroundColor Red
    }
}

if ($failed -eq 0) {
    Write-Host "`nPASS: native cross-database queries work on $Server." -ForegroundColor Green
    exit 0
}
Write-Host "`nFAIL: $failed of $($checks.Count) checks failed. Msg 40515 means three-part names are not enabled for this server/pool." -ForegroundColor Red
exit 1
