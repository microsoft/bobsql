[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ExpectedServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"
$connection = $null
$previousPath = $env:PATH
$watch = [Diagnostics.Stopwatch]::StartNew()
$target = 18L * 1GB
$allocationTarget = 20L * 1GB

function Invoke-StorageSql {
    param([string]$Sql, [hashtable]$Parameters = @{}, [int]$Timeout = 120)
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = "IF DB_NAME() <> N'caldova-scheduling' THROW 50000, 'Wrong reset database.', 1;`n$Sql"
        $command.CommandTimeout = $Timeout
        foreach ($name in $Parameters.Keys) {
            $parameter = $command.Parameters.Add($name, [System.Data.SqlDbType]::BigInt)
            $parameter.Value = [long]$Parameters[$name]
        }
        return $command.ExecuteScalar()
    }
    finally { $command.Dispose() }
}

function Read-Storage {
    $command = $connection.CreateCommand()
    $reader = $null
    try {
        $command.CommandText = @'
IF DB_NAME() <> N'caldova-scheduling' THROW 50000, 'Wrong reset database.', 1;
SELECT UsedBytes, AllocatedBytes, DataFiles, MissingFiles,
    (SELECT SUM(row_count) FROM sys.dm_db_partition_stats
        WHERE object_id=OBJECT_ID(N'demo.StoragePayload') AND index_id=1),
    (SELECT SUM(used_page_count)*CONVERT(bigint,8192) FROM sys.dm_db_partition_stats
        WHERE object_id=OBJECT_ID(N'demo.StoragePayload')),
    (SELECT COUNT_BIG(*) FROM dbo.AppointmentSlot),
    (SELECT COUNT_BIG(*) FROM dbo.Appointment),
    (SELECT COUNT_BIG(*) FROM network.ProviderClinic)
FROM demo.StorageSize;
'@
        $command.CommandTimeout = 30
        $reader = $command.ExecuteReader()
        if (-not $reader.Read() -or $reader.IsDBNull(0) -or $reader.IsDBNull(1) -or
            $reader.IsDBNull(4) -or $reader.IsDBNull(5) -or
            $reader.GetInt32(2) -ne 1 -or $reader.GetInt32(3) -ne 0) {
            throw 'Reset requires one fully measured data file and the existing synthetic payload table.'
        }
        return [pscustomobject]@{
            UsedBytes = $reader.GetInt64(0)
            AllocatedBytes = $reader.GetInt64(1)
            PayloadRows = $reader.GetInt64(4)
            PayloadBytes = $reader.GetInt64(5)
            Slots = $reader.GetInt64(6)
            Appointments = $reader.GetInt64(7)
            Providers = $reader.GetInt64(8)
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $command.Dispose()
    }
}

function Write-Storage {
    param([string]$Phase, [object]$Storage)
    Write-Host ("{0}: {1:N3} GiB used / {2:N3} GiB allocated ({3:N1}s elapsed)" -f
        $Phase, ($Storage.UsedBytes / 1GB), ($Storage.AllocatedBytes / 1GB), $watch.Elapsed.TotalSeconds)
}

try {
    $account = Invoke-Az @('account', 'show', '--query', '{name:name,id:id}', '--output', 'json')
    if ($account.id -ne $SubscriptionId -or $ExpectedServerName -ne $SqlServerName -or
        $SqlServerName -notlike 'sql-caldova-network-*' -or $CaldovaDatabase -ne 'caldova-scheduling') {
        throw 'Reset target differs from the current CLI subscription or the explicitly expected Grow server.'
    }
    $poolBefore = Invoke-Az @('sql', 'elastic-pool', 'show', '-g', $ResourceGroup,
        '-s', $SqlServerName, '-n', $ElasticPoolName, '--output', 'json')
    if ($poolBefore.state -ne 'Ready' -or $poolBefore.sku.tier -ne 'Hyperscale') {
        throw 'The existing Hyperscale pool must be Ready before reset.'
    }
    $databasesBefore = @(Invoke-Az @('sql', 'db', 'list', '-g', $ResourceGroup,
        '-s', $SqlServerName, '--output', 'json'))
    foreach ($name in @($CaldovaDatabase) + @($AcquiredDatabases.Name)) {
        $database = @($databasesBefore | Where-Object name -EQ $name)
        if ($database.Count -ne 1 -or $database[0].status -ne 'Online' -or
            $database[0].elasticPoolId -ne $poolBefore.id) {
            throw "$name must be Online in the existing pool."
        }
    }
    Write-Host "Target: $($account.name); $ResourceGroup; $SqlServerName; $CaldovaDatabase"
    Write-Host 'Stop the local app and its workload before applying this off-camera reset.'
    Write-Host 'Truncate only demo.StoragePayload; shrink data_0 toward 20 GiB; refill to 18 GiB used.'
    Write-Host 'Preserve scheduling tables, bookings, provider directory, other databases, pool, servers, and preview settings.'
    if (-not $PSCmdlet.ShouldProcess("$SqlServerName : $CaldovaDatabase",
        'Replace synthetic storage payload and restore 18 GiB used / 20 GiB allocated')) { return }

    $bin = Join-Path $PSScriptRoot '..\app\bin\Release\net10.0'
    $env:PATH = (Join-Path $bin 'runtimes\win-x64\native') + ';' + $env:PATH
    Add-Type -Path (Join-Path $bin 'Microsoft.SqlServer.Server.dll')
    Add-Type -Path (Join-Path $bin 'runtimes\win\lib\net9.0\Microsoft.Data.SqlClient.dll')
    $token = Invoke-Az @('account', 'get-access-token', '--resource', 'https://database.windows.net/',
        '--query', '{accessToken:accessToken}', '--output', 'json')
    $connection = [Microsoft.Data.SqlClient.SqlConnection]::new(
        "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$CaldovaDatabase;Encrypt=True;TrustServerCertificate=False;Connect Timeout=30;ConnectRetryCount=0;Pooling=False")
    $connection.AccessToken = $token.accessToken
    $token = $null
    $connection.Open()
    Invoke-StorageSql @'
IF COL_LENGTH(N'demo.StoragePayload', N'Payload') <> 7800
    OR COLUMNPROPERTY(OBJECT_ID(N'demo.StoragePayload'), N'RowId', 'IsIdentity') <> 1
    OR EXISTS (SELECT 1 FROM sys.partitions
        WHERE object_id=OBJECT_ID(N'demo.StoragePayload') AND data_compression<>0)
    OR EXISTS (SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id=OBJECT_ID(N'demo.StoragePayload')
           OR referenced_object_id=OBJECT_ID(N'demo.StoragePayload'))
    THROW 50001, 'Unexpected payload schema or relationships; reset refused.', 1;
IF (SELECT COUNT(*) FROM sys.database_files WHERE type=0) <> 1
    OR NOT EXISTS (SELECT 1 FROM sys.database_files WHERE file_id=1 AND name=N'data_0' AND type=0)
    THROW 50002, 'Unexpected data-file layout; reset refused.', 1;
SELECT 1;
'@ | Out-Null
    $before = Read-Storage
    Write-Storage 'Before reset' $before
    $preservedBytes = $before.UsedBytes - $before.PayloadBytes
    $schemaBefore = [string](Invoke-StorageSql @'
SELECT STRING_AGG(CONVERT(nvarchar(max), CONCAT(SCHEMA_NAME(schema_id), N'.', name, N':', type,
    N':', COALESCE(OBJECT_DEFINITION(object_id), N''))) COLLATE DATABASE_DEFAULT, N'|' COLLATE DATABASE_DEFAULT)
    WITHIN GROUP (ORDER BY schema_id, name)
FROM sys.objects WHERE is_ms_shipped=0 AND schema_id<>SCHEMA_ID(N'demo');
'@)

    Invoke-StorageSql @'
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @lock int;
EXEC @lock=sys.sp_getapplock @Resource=N'Caldova.DemoStorageFill',
    @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=0;
IF @lock<0 THROW 50003, 'Another storage writer is active; reset refused.', 1;
TRUNCATE TABLE demo.StoragePayload;
COMMIT TRANSACTION;
SELECT 1;
'@ | Out-Null
    $deallocation = [Diagnostics.Stopwatch]::StartNew()
    do {
        $current = Read-Storage
        if ($current.PayloadRows -ne 0) { throw 'Another writer added payload rows during reset.' }
        if ($current.UsedBytes -le $preservedBytes + 64MB) { break }
        if ($deallocation.Elapsed.TotalMinutes -ge 2) { throw 'Synthetic page deallocation exceeded two minutes; inspect before continuing.' }
        Start-Sleep -Seconds 5
    } while ($true)
    Write-Storage 'Payload cleared' $current
    Invoke-StorageSql 'DBCC SHRINKFILE (1, 20480);' -Timeout 300 | Out-Null
    $current = Read-Storage
    Write-Storage 'After shrink' $current
    if ($current.AllocatedBytes -gt $allocationTarget) {
        throw 'Shrink did not reduce allocation to 20 GiB; no refill started.'
    }

    $fill = [Diagnostics.Stopwatch]::StartNew()
    $nextReport = 1.0
    while ($current.UsedBytes -lt $target) {
        if ($fill.Elapsed.TotalMinutes -ge 20) { throw 'Reset refill exceeded twenty minutes; committed batches remain. Inspect before continuing.' }
        $rows = Invoke-StorageSql 'EXEC demo.FillStorageBatch @TargetBytes=@target, @MaxRows=4096;' `
            -Parameters @{ '@target' = $target }
        if ($null -eq $rows -or [long]$rows -le 0) { throw 'Refill inserted no rows; inspect for concurrent changes.' }
        $next = Read-Storage
        if ($next.UsedBytes -le $current.UsedBytes -or $next.UsedBytes -gt $target + 64MB) {
            throw 'Refill measurements did not increase within the approved target tolerance.'
        }
        $current = $next
        if ($current.UsedBytes / 1GB -ge $nextReport) {
            Write-Storage 'Refilling synthetic data' $current
            $nextReport = [Math]::Floor($current.UsedBytes / 1GB) + 1
        }
    }
    $after = Read-Storage
    if ($after.UsedBytes -lt $target -or $after.UsedBytes -gt $target + 64MB -or
        $after.AllocatedBytes -ne $allocationTarget) {
        throw 'Final storage is not within 18-GiB used tolerance with exactly 20 GiB allocated.'
    }
    if ($after.Slots -ne $before.Slots -or $after.Appointments -ne $before.Appointments -or
        $after.Providers -ne $before.Providers) {
        throw 'Scheduling or provider-directory row counts changed during reset.'
    }
    $schemaAfter = [string](Invoke-StorageSql @'
SELECT STRING_AGG(CONVERT(nvarchar(max), CONCAT(SCHEMA_NAME(schema_id), N'.', name, N':', type,
    N':', COALESCE(OBJECT_DEFINITION(object_id), N''))) COLLATE DATABASE_DEFAULT, N'|' COLLATE DATABASE_DEFAULT)
    WITHIN GROUP (ORDER BY schema_id, name)
FROM sys.objects WHERE is_ms_shipped=0 AND schema_id<>SCHEMA_ID(N'demo');
'@)
    if ($schemaAfter -ne $schemaBefore) { throw 'Non-demo object definitions changed during reset.' }
    $poolAfter = Invoke-Az @('sql', 'elastic-pool', 'show', '-g', $ResourceGroup,
        '-s', $SqlServerName, '-n', $ElasticPoolName, '--output', 'json')
    if ($poolAfter.state -ne 'Ready' -or $poolAfter.sku.name -ne $poolBefore.sku.name -or
        $poolAfter.sku.capacity -ne $poolBefore.sku.capacity -or
        $poolAfter.perDatabaseSettings.minCapacity -ne $poolBefore.perDatabaseSettings.minCapacity -or
        $poolAfter.perDatabaseSettings.maxCapacity -ne $poolBefore.perDatabaseSettings.maxCapacity -or
        $poolAfter.zoneRedundant -ne $poolBefore.zoneRedundant) {
        throw 'Pool configuration differs from its pre-reset state.'
    }
    $databasesAfter = @(Invoke-Az @('sql', 'db', 'list', '-g', $ResourceGroup,
        '-s', $SqlServerName, '--output', 'json'))
    foreach ($database in $databasesBefore | Where-Object name -NE 'master') {
        $match = @($databasesAfter | Where-Object name -EQ $database.name)
        if ($match.Count -ne 1 -or $match[0].status -ne 'Online' -or
            $match[0].elasticPoolId -ne $database.elasticPoolId -or
            $match[0].currentBackupStorageRedundancy -ne $database.currentBackupStorageRedundancy) {
            throw "$($database.name) placement, availability, or backup configuration changed."
        }
    }
    Write-Storage 'Reset verified' $after
    Write-Host "Preserved: $($after.Slots) slots; $($after.Appointments) appointments; $($after.Providers) provider rows; non-demo schema; all provider databases and pool settings."
}
catch {
    throw ($_.Exception.Message -replace '(?i)[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', '[redacted-id]')
}
finally {
    if ($null -ne $connection) { $connection.Dispose() }
    $env:PATH = $previousPath
}
