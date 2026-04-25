<#
.SYNOPSIS
    Checks whether a laptop is ready to run the SQL Server Versioning demos.

.DESCRIPTION
    Validates local files, demo tooling, optional page-viewer dependencies,
    and SQL Server connectivity/features needed by the SQLBits 2026 SQL
    Versioning session.

.PARAMETER ServerName
    SQL Server instance to test. Default: localhost.

.PARAMETER MainDatabase
    Main demo database name created by demo0-setup.sql.

.PARAMETER SqlsimPath
    Path to sqlsim.exe used by the benchmark demo.

.PARAMETER OutputJson
    Emit the result object as JSON in addition to the console summary.

.EXAMPLE
    .\check-readiness.ps1

.EXAMPLE
    .\check-readiness.ps1 -ServerName ".\SQL2025" -OutputJson
#>

[CmdletBinding()]
param(
    [string]$ServerName = 'localhost',
    [string]$MainDatabase = 'texasrangerswillwinitthisyear',
    [string]$SqlsimPath = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe',
    [switch]$OutputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Results = New-Object System.Collections.Generic.List[object]
$demoRoot = Split-Path -Parent $PSCommandPath
$sessionRoot = Split-Path -Parent $demoRoot

function Add-Result {
    param(
        [string]$Category,
        [string]$Name,
        [ValidateSet('PASS', 'WARN', 'FAIL', 'SKIP')]
        [string]$Status,
        [string]$Message,
        [string]$Recommendation = '',
        [hashtable]$Details = @{}
    )

    $script:Results.Add([pscustomobject]@{
        Category = $Category
        Name = $Name
        Status = $Status
        Message = $Message
        Recommendation = $Recommendation
        Details = $Details
    }) | Out-Null
}

function Get-StatusColor {
    param([string]$Status)

    switch ($Status) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'DarkGray' }
    }
}

function Test-CommandPath {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    return $command.Source
}

function Invoke-SqlQuery {
    param(
        [string]$Database,
        [string]$Query
    )

    $connectionString = "Server=$ServerName;Database=$Database;Integrated Security=true;Encrypt=False;TrustServerCertificate=True;Connection Timeout=5"
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    $command = $connection.CreateCommand()
    $command.CommandTimeout = 10
    $command.CommandText = $Query

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $table = New-Object System.Data.DataTable

    try {
        $connection.Open()
        [void]$adapter.Fill($table)
        return ,$table
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }
        $connection.Dispose()
        $adapter.Dispose()
    }
}

function Add-FileChecks {
    $requiredFiles = @(
        'demo1-blocking.sql',
        'demo2a-rcsi.sql',
        'demo2b-rcsi-vs-snapshot.sql',
        'demo2c-snapshot-conflict.sql',
        'demo3a-version-chain.sql',
        'demo3b-version-store-growth.sql',
        'demo4-adr-recovery.sql',
        'demo5-optimized-locking.sql',
        'demo6-benchmark.sql',
        'demo6-run-benchmark.ps1',
        'check-readiness.ps1'
    )

    $missing = @()
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path (Join-Path $demoRoot $file))) {
            $missing += $file
        }
    }

    if ($missing.Count -eq 0) {
        Add-Result -Category 'Files' -Name 'Demo assets' -Status 'PASS' -Message 'All core demo scripts are present.' -Details @{ DemoRoot = $demoRoot }
    }
    else {
        Add-Result -Category 'Files' -Name 'Demo assets' -Status 'FAIL' -Message ('Missing demo files: ' + ($missing -join ', ')) -Recommendation 'Sync the repo or restore the missing files before presenting.' -Details @{ DemoRoot = $demoRoot }
    }

    if (Test-Path (Join-Path $sessionRoot 'RUNBOOK.md')) {
        Add-Result -Category 'Files' -Name 'Runbook' -Status 'PASS' -Message 'RUNBOOK.md is present.'
    }
    else {
        Add-Result -Category 'Files' -Name 'Runbook' -Status 'WARN' -Message 'RUNBOOK.md is missing.' -Recommendation 'Recreate the runbook or rely on the demo scripts directly.'
    }
}

function Add-ToolChecks {
    if (Test-Path $SqlsimPath) {
        Add-Result -Category 'Tools' -Name 'sqlsim' -Status 'PASS' -Message "sqlsim.exe found at $SqlsimPath"
    }
    else {
        Add-Result -Category 'Tools' -Name 'sqlsim' -Status 'FAIL' -Message "sqlsim.exe not found at $SqlsimPath" -Recommendation 'Build or copy sqlsim.exe before running the benchmark demo.'
    }

    $ssmsPaths = @(
        'C:\Program Files\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio 21\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe'
    )

    $ssms = $ssmsPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($ssms) {
        Add-Result -Category 'Tools' -Name 'SSMS' -Status 'PASS' -Message "SSMS found at $ssms"
    }
    else {
        Add-Result -Category 'Tools' -Name 'SSMS' -Status 'WARN' -Message 'SSMS not found in standard install locations.' -Recommendation 'Install SSMS or use another SQL client with multiple query windows.'
    }

    $pythonPath = Test-CommandPath -Name 'python'
    if ($pythonPath) {
        Add-Result -Category 'Tools' -Name 'Python' -Status 'PASS' -Message "python found at $pythonPath"
    }
    else {
        $pyPath = Test-CommandPath -Name 'py'
        if ($pyPath) {
            Add-Result -Category 'Tools' -Name 'Python launcher' -Status 'PASS' -Message "py launcher found at $pyPath"
        }
        else {
            Add-Result -Category 'Tools' -Name 'Python' -Status 'WARN' -Message 'Python was not found.' -Recommendation 'Install Python if you want to run the optional page viewer demo.'
        }
    }

    $sqlcmdPath = Test-CommandPath -Name 'sqlcmd'
    if ($sqlcmdPath) {
        Add-Result -Category 'Tools' -Name 'sqlcmd' -Status 'PASS' -Message "sqlcmd found at $sqlcmdPath"
    }
    else {
        Add-Result -Category 'Tools' -Name 'sqlcmd' -Status 'WARN' -Message 'sqlcmd was not found.' -Recommendation 'Optional, but useful for quick manual validation outside the scripted demos.'
    }

    try {
        $driver = Get-OdbcDriver -Name 'ODBC Driver 18 for SQL Server' -ErrorAction Stop | Select-Object -First 1
        Add-Result -Category 'Tools' -Name 'ODBC Driver 18' -Status 'PASS' -Message 'ODBC Driver 18 for SQL Server is installed.' -Details @{ Platform = $driver.Platform }
    }
    catch {
        Add-Result -Category 'Tools' -Name 'ODBC Driver 18' -Status 'WARN' -Message 'ODBC Driver 18 for SQL Server is not installed.' -Recommendation 'Install it if you plan to use dbcc_page_viewer.py.'
    }

    if ($pythonPath) {
        try {
            & $pythonPath -c "import flask, pyodbc" *> $null
            Add-Result -Category 'Tools' -Name 'Python packages' -Status 'PASS' -Message 'flask and pyodbc imports succeeded.'
        }
        catch {
            Add-Result -Category 'Tools' -Name 'Python packages' -Status 'WARN' -Message 'flask and/or pyodbc are not importable.' -Recommendation 'Run pip install flask pyodbc if you want the page viewer demo.'
        }
    }
    else {
        Add-Result -Category 'Tools' -Name 'Python packages' -Status 'SKIP' -Message 'Python not available, so package import checks were skipped.'
    }
}

function Add-SqlChecks {
    try {
        $serverInfo = Invoke-SqlQuery -Database 'master' -Query @"
SELECT
    CAST(SERVERPROPERTY('ServerName') AS nvarchar(256)) AS ServerName,
    CAST(SERVERPROPERTY('MachineName') AS nvarchar(256)) AS MachineName,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(256)) AS Edition,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS ProductVersion,
    TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS int) AS ProductMajorVersion,
    TRY_CAST(SERVERPROPERTY('EngineEdition') AS int) AS EngineEdition;
"@

        if ($serverInfo.Rows.Count -eq 0) {
            throw 'No rows returned from server metadata query.'
        }

        $row = $serverInfo.Rows[0]
        $major = if ($row.ProductMajorVersion -is [System.DBNull]) { $null } else { [int]$row.ProductMajorVersion }
        Add-Result -Category 'SQL' -Name 'Connectivity' -Status 'PASS' -Message "Connected to $($row.ServerName) ($($row.Edition))" -Details @{ ProductVersion = $row.ProductVersion; EngineEdition = $row.EngineEdition }

        if ($major -ge 17) {
            Add-Result -Category 'SQL' -Name 'SQL Server version' -Status 'PASS' -Message "Server major version is $major, which is suitable for SQL Server 2025 demos."
        }
        elseif ($null -ne $major) {
            Add-Result -Category 'SQL' -Name 'SQL Server version' -Status 'FAIL' -Message "Server major version is $major, below the SQL Server 2025 requirement for the full local demo set." -Recommendation 'Use a SQL Server 2025 instance for full readiness, especially for Optimized Locking.'
        }
        else {
            Add-Result -Category 'SQL' -Name 'SQL Server version' -Status 'WARN' -Message 'Could not determine ProductMajorVersion.' -Recommendation 'Manually verify you are on SQL Server 2025.'
        }

        $permissions = Invoke-SqlQuery -Database 'master' -Query @"
SELECT
    IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin,
    HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW SERVER STATE') AS ViewServerState,
    HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY DATABASE') AS AlterAnyDatabase;
"@

        $perm = $permissions.Rows[0]
        if ([int]$perm.IsSysadmin -eq 1) {
            Add-Result -Category 'SQL' -Name 'Permissions' -Status 'PASS' -Message 'Current login is sysadmin.'
        }
        elseif (([int]$perm.ViewServerState -eq 1) -and ([int]$perm.AlterAnyDatabase -eq 1)) {
            Add-Result -Category 'SQL' -Name 'Permissions' -Status 'WARN' -Message 'Current login has key permissions but is not sysadmin.' -Recommendation 'Most demos may work, but DBCC PAGE and some server-level checks can still be blocked.'
        }
        else {
            Add-Result -Category 'SQL' -Name 'Permissions' -Status 'FAIL' -Message 'Current login lacks one or more required privileges.' -Recommendation 'Use a sysadmin login or grant VIEW SERVER STATE and ALTER ANY DATABASE.'
        }

        $dbs = Invoke-SqlQuery -Database 'master' -Query @"
SELECT name, state_desc
FROM sys.databases
WHERE name IN (N'$MainDatabase', N'eaglesdontfly', N'howboutthemcowboys')
ORDER BY name;
"@

        $dbNames = @($dbs.Rows | ForEach-Object { $_.name })
        $missingDbs = @($MainDatabase, 'eaglesdontfly', 'howboutthemcowboys' | Where-Object { $_ -notin $dbNames })
        if ($missingDbs.Count -eq 0) {
            Add-Result -Category 'SQL' -Name 'Setup databases' -Status 'PASS' -Message 'All setup databases exist.'
        }
        else {
            Add-Result -Category 'SQL' -Name 'Setup databases' -Status 'WARN' -Message ('Missing setup databases: ' + ($missingDbs -join ', ')) -Recommendation 'Run demo0-setup.sql before the session.'
        }

        if ($dbNames -contains $MainDatabase) {
            $featureInfo = Invoke-SqlQuery -Database 'master' -Query @"
SELECT
    name,
    state_desc,
    user_access_desc,
    is_read_committed_snapshot_on,
    snapshot_isolation_state_desc,
    CASE WHEN COL_LENGTH('sys.databases', 'is_accelerated_database_recovery_on') IS NOT NULL THEN is_accelerated_database_recovery_on ELSE NULL END AS ADR,
    DATABASEPROPERTYEX(name, 'IsOptimizedLockingOn') AS IsOptimizedLockingOn
FROM sys.databases
WHERE name = N'$MainDatabase';
"@

            $feature = $featureInfo.Rows[0]
            $optLock = if ($feature.IsOptimizedLockingOn -is [System.DBNull]) { $null } else { [int]$feature.IsOptimizedLockingOn }

            if ($feature.state_desc -eq 'ONLINE') {
                Add-Result -Category 'SQL' -Name 'Main database state' -Status 'PASS' -Message "$MainDatabase is ONLINE and $($feature.user_access_desc)."
            }
            else {
                Add-Result -Category 'SQL' -Name 'Main database state' -Status 'FAIL' -Message "$MainDatabase is $($feature.state_desc)." -Recommendation 'Bring the database online or rerun demo0-setup.sql.'
            }

            if ($null -eq $optLock) {
                Add-Result -Category 'SQL' -Name 'Optimized Locking support' -Status 'FAIL' -Message 'DATABASEPROPERTYEX(..., IsOptimizedLockingOn) returned NULL.' -Recommendation 'Use a SQL Server 2025 build that supports Optimized Locking.'
            }
            else {
                Add-Result -Category 'SQL' -Name 'Optimized Locking support' -Status 'PASS' -Message 'Optimized Locking property is available on this server.' -Details @{ CurrentValue = $optLock }
            }

            $objects = Invoke-SqlQuery -Database $MainDatabase -Query @"
SELECT
    OBJECT_ID(N'dbo.Accounts') AS AccountsId,
    OBJECT_ID(N'dbo.Orders') AS OrdersId,
    OBJECT_ID(N'dbo.OrderItems') AS OrderItemsId,
    OBJECT_ID(N'dbo.BigTable') AS BigTableId,
    OBJECT_ID(N'dbo.BenchAccounts') AS BenchAccountsId,
    OBJECT_ID(N'dbo.usp_BenchmarkWorkload') AS BenchmarkProcId,
    OBJECT_ID(N'dbo.BenchmarkResults') AS BenchmarkResultsId;
"@

            $obj = $objects.Rows[0]
            $missingCoreObjects = @()
            foreach ($pair in @{
                'Accounts' = $obj.AccountsId
                'Orders' = $obj.OrdersId
                'OrderItems' = $obj.OrderItemsId
                'BigTable' = $obj.BigTableId
                'BenchAccounts' = $obj.BenchAccountsId
            }.GetEnumerator()) {
                if ($pair.Value -is [System.DBNull] -or [int]$pair.Value -le 0) {
                    $missingCoreObjects += $pair.Key
                }
            }

            if ($missingCoreObjects.Count -eq 0) {
                Add-Result -Category 'SQL' -Name 'Core demo objects' -Status 'PASS' -Message 'Core demo tables exist in the main database.'
            }
            else {
                Add-Result -Category 'SQL' -Name 'Core demo objects' -Status 'FAIL' -Message ('Missing core demo objects: ' + ($missingCoreObjects -join ', ')) -Recommendation 'Rerun demo0-setup.sql.'
            }

            if (($obj.BenchmarkProcId -isnot [System.DBNull]) -and ([int]$obj.BenchmarkProcId -gt 0) -and ($obj.BenchmarkResultsId -isnot [System.DBNull]) -and ([int]$obj.BenchmarkResultsId -gt 0)) {
                Add-Result -Category 'SQL' -Name 'Benchmark objects' -Status 'PASS' -Message 'Benchmark stored procedure and results table exist.'
            }
            else {
                Add-Result -Category 'SQL' -Name 'Benchmark objects' -Status 'WARN' -Message 'Benchmark objects are not fully created yet.' -Recommendation 'Run demo6-benchmark.sql before running demo6-run-benchmark.ps1.'
            }
        }
        else {
            Add-Result -Category 'SQL' -Name 'Main database state' -Status 'SKIP' -Message 'Main database does not exist yet, so deeper database checks were skipped.'
            Add-Result -Category 'SQL' -Name 'Optimized Locking support' -Status 'SKIP' -Message 'Main database does not exist yet, so the database property check was skipped.'
            Add-Result -Category 'SQL' -Name 'Core demo objects' -Status 'SKIP' -Message 'Main database does not exist yet, so object checks were skipped.'
            Add-Result -Category 'SQL' -Name 'Benchmark objects' -Status 'SKIP' -Message 'Main database does not exist yet, so benchmark object checks were skipped.'
        }
    }
    catch {
        Add-Result -Category 'SQL' -Name 'Connectivity' -Status 'FAIL' -Message $_.Exception.Message -Recommendation 'Start the target SQL Server instance or pass the correct -ServerName.'
        Add-Result -Category 'SQL' -Name 'SQL Server version' -Status 'SKIP' -Message 'Connectivity failed, so version check was skipped.'
        Add-Result -Category 'SQL' -Name 'Permissions' -Status 'SKIP' -Message 'Connectivity failed, so permission checks were skipped.'
        Add-Result -Category 'SQL' -Name 'Setup databases' -Status 'SKIP' -Message 'Connectivity failed, so database checks were skipped.'
        Add-Result -Category 'SQL' -Name 'Main database state' -Status 'SKIP' -Message 'Connectivity failed, so main database checks were skipped.'
        Add-Result -Category 'SQL' -Name 'Optimized Locking support' -Status 'SKIP' -Message 'Connectivity failed, so feature checks were skipped.'
        Add-Result -Category 'SQL' -Name 'Core demo objects' -Status 'SKIP' -Message 'Connectivity failed, so object checks were skipped.'
        Add-Result -Category 'SQL' -Name 'Benchmark objects' -Status 'SKIP' -Message 'Connectivity failed, so benchmark checks were skipped.'
    }
}

function Show-Summary {
    Write-Host ''
    Write-Host 'SQL Versioning Demo Readiness' -ForegroundColor Cyan
    Write-Host ('Server: ' + $ServerName) -ForegroundColor Cyan
    Write-Host ('Demo root: ' + $demoRoot) -ForegroundColor Cyan
    Write-Host ''

    foreach ($result in $script:Results) {
        $prefix = ('[{0}]' -f $result.Status).PadRight(7)
        Write-Host ($prefix + ' ' + $result.Category + ' - ' + $result.Name + ': ' + $result.Message) -ForegroundColor (Get-StatusColor -Status $result.Status)
        if ($result.Recommendation) {
            Write-Host ('        Next: ' + $result.Recommendation) -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    $counts = $script:Results | Group-Object Status | Sort-Object Name
    foreach ($status in 'FAIL', 'WARN', 'PASS', 'SKIP') {
        $match = $counts | Where-Object { $_.Name -eq $status }
        $count = if ($match) { $match.Count } else { 0 }
        Write-Host (('{0}: {1}' -f $status.PadRight(4), $count)) -ForegroundColor (Get-StatusColor -Status $status)
    }

    $failCount = @($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warnCount = @($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count
    Write-Host ''
    if ($failCount -gt 0) {
        Write-Host 'Overall readiness: NOT READY' -ForegroundColor Red
    }
    elseif ($warnCount -gt 0) {
        Write-Host 'Overall readiness: PARTIAL' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Overall readiness: READY' -ForegroundColor Green
    }
}

Add-FileChecks
Add-ToolChecks
Add-SqlChecks
Show-Summary

if ($OutputJson) {
    $payload = [pscustomobject]@{
        ServerName = $ServerName
        MainDatabase = $MainDatabase
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Results = $script:Results
    }
    Write-Host ''
    $payload | ConvertTo-Json -Depth 6
}

$failures = @($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
if ($failures -gt 0) {
    exit 1
}

exit 0