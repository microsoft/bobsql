#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Journal = $null
$script:CancelFile = $null

class StudioBlockedException : System.Exception {
    [string] $Code
    StudioBlockedException([string] $code, [string] $message) : base($message) { $this.Code = $code }
}

function Stop-StudioOperation {
    param([string] $Code, [string] $Message)
    throw [StudioBlockedException]::new($Code, $Message)
}

function Write-StudioEvent {
    param([string] $Stage, [string] $State, [string] $Message)
    $event = @{ stage = $Stage; state = $State; message = $Message }
    $json = ConvertTo-Json -InputObject $event -Compress
    [Console]::Out.WriteLine("STUDIO_EVENT $json")
    if ($script:Journal) {
        [IO.File]::AppendAllText($script:Journal, "$json`n")
    }
}

function Set-StudioRunContext {
    param([string] $Directory)
    $script:Journal = Join-Path $Directory 'engine-events.ndjson'
    $script:CancelFile = Join-Path $Directory 'cancel.request'
}

function Assert-StudioNotCancelled {
    if ($script:CancelFile -and [IO.File]::Exists($script:CancelFile)) {
        Stop-StudioOperation 'Cancelled' 'Cancellation requested. Partial target resources are retained; re-inspect before retrying.'
    }
}

function Assert-StudioLocalPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or
        $Path.Contains('..') -or $Path.Substring(2).Contains(':')) {
        Stop-StudioOperation 'InvalidPath' 'Use an absolute local Windows path without traversal or alternate streams.'
    }
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                Stop-StudioOperation 'InvalidPath' 'Reparse points are not allowed in request or evidence paths.'
            }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}

function Protect-StudioDirectory {
    param([string] $Path)
    Assert-StudioLocalPath $Path
    [void][IO.Directory]::CreateDirectory($Path)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($identity in @($sid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl',
            'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Assert-StudioProtectedFile {
    param([string] $Path)
    Assert-StudioLocalPath $Path
    if (-not [IO.File]::Exists($Path) -or (Get-Item -LiteralPath $Path).Length -gt 65536) {
        Stop-StudioOperation 'InvalidRequest' 'A protected request JSON file smaller than 64 KiB is required.'
    }
    $acl = Get-Acl -LiteralPath $Path
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid) {
        Stop-StudioOperation 'UnprotectedRequest' 'The request file must belong to the current Windows identity.'
    }
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -eq 'Allow' -and
            $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @($sid, 'S-1-5-18')) {
            Stop-StudioOperation 'UnprotectedRequest' 'Restrict request file access to the current Windows identity and SYSTEM.'
        }
    }
}

function Assert-StudioConfiguration {
    param([System.Collections.IDictionary] $Config, [string] $Operation)
    $allowed = @('containerName','sourceDatabase','tenantId','subscriptionId','region','resourceGroup',
        'createResourceGroup','serverName','createServer','targetDatabase','authentication','runDirectory',
        'confirmation','writersStopped')
    foreach ($key in $Config.Keys) {
        if ($key -notin $allowed) { Stop-StudioOperation 'InvalidRequest' 'The request contains an unsupported field.' }
    }
    if ($Config.Contains('containerName') -and $Config.containerName -cne 'sqldbcontainer') {
        Stop-StudioOperation 'SourceNotApproved' 'Only the approved sqldbcontainer source can be queried.'
    }
    foreach ($key in @('sourceDatabase','targetDatabase')) {
        if ($Config.Contains($key) -and ($Config[$key] -isnot [string] -or
            $Config[$key] -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,127}$' -or
            $Config[$key] -in @('master','model','msdb','tempdb'))) {
            Stop-StudioOperation 'InvalidDatabase' 'Choose a named user database using letters, digits, underscores, or hyphens.'
        }
    }
    foreach ($key in @('tenantId','subscriptionId')) {
        if ($Config.Contains($key) -and $Config[$key] -notmatch '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$') {
            Stop-StudioOperation 'InvalidAzureSelection' 'Tenant and subscription IDs must be GUIDs.'
        }
    }
    foreach ($key in @('createResourceGroup','createServer','writersStopped')) {
        if ($Config.Contains($key) -and $Config[$key] -isnot [bool]) {
            Stop-StudioOperation 'InvalidRequest' 'Creation and writer acknowledgments must be JSON booleans.'
        }
    }
    if ($Config.Contains('resourceGroup') -and $Config.resourceGroup -notmatch '^[A-Za-z0-9_()-][A-Za-z0-9_().-]{0,88}[A-Za-z0-9_()-]$') {
        Stop-StudioOperation 'InvalidAzureSelection' 'The resource group name is invalid.'
    }
    if ($Config.Contains('serverName') -and $Config.serverName -notmatch '^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$') {
        Stop-StudioOperation 'InvalidAzureSelection' 'The logical server name is invalid.'
    }
    if ($Config.Contains('region') -and $Config.region -notmatch '^[a-z][a-z0-9]{1,39}$') {
        Stop-StudioOperation 'InvalidAzureSelection' 'Choose an Azure region returned by discovery.'
    }
    if ($Config.Contains('authentication') -and $Config.authentication -cne 'Entra') {
        Stop-StudioOperation 'AuthenticationNotApproved' 'Only Microsoft Entra target authentication is supported.'
    }
    if ($Operation -eq 'Migrate') {
        foreach ($key in @('containerName','sourceDatabase','tenantId','subscriptionId','region','resourceGroup',
            'createResourceGroup','serverName','createServer','targetDatabase','authentication','runDirectory','confirmation','writersStopped')) {
            if (-not $Config.Contains($key) -or $null -eq $Config[$key] -or "$($Config[$key])" -eq '') {
                Stop-StudioOperation 'InvalidRequest' 'The complete immutable migration configuration is required.'
            }
        }
        if ($Config.confirmation -cne 'CREATE FREE DATABASE AND MIGRATE') {
            Stop-StudioOperation 'ApprovalRequired' 'The exact migration confirmation is required.'
        }
        if ($Config.writersStopped -ne $true) {
            Stop-StudioOperation 'QuiescenceRequired' 'Approve and establish write quiescence before migration.'
        }
        Assert-StudioLocalPath $Config.runDirectory
    }
}

function Invoke-StudioNative {
    param([string] $File, [string[]] $Arguments, [switch] $AllowFailure)
    Assert-StudioNotCancelled
    $command = Get-Command $File -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { Stop-StudioOperation 'MissingTool' 'A required local command is unavailable. Run preflight.' }
    $executable = $command.Source
    if ($executable.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase)) {
        if ($File -ne 'az') { Stop-StudioOperation 'UnsupportedTool' 'Only native executables and the installed Azure CLI are allowed.' }
        $python = Join-Path (Split-Path (Split-Path $executable)) 'python.exe'
        if (-not (Test-Path -LiteralPath $python)) {
            Stop-StudioOperation 'MissingTool' 'The Azure CLI Python installation could not be resolved safely.'
        }
        $executable = $python
        $Arguments = @('-IBm','azure.cli') + $Arguments
    }
    $info = [Diagnostics.ProcessStartInfo]::new($executable)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(250)) {
            if ($script:CancelFile -and [IO.File]::Exists($script:CancelFile)) {
                $process.Kill($true)
                $process.WaitForExit()
                Assert-StudioNotCancelled
            }
        }
        $text = $stdout.GetAwaiter().GetResult()
        [void]$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -and -not $AllowFailure) {
            Stop-StudioOperation 'ToolFailed' 'A required local tool failed. Check sign-in, permissions, network, and tool versions; raw diagnostics are withheld.'
        }
        return @{ exitCode = $process.ExitCode; output = $text }
    } finally { $process.Dispose() }
}

function Invoke-StudioAz {
    param([string[]] $Arguments)
    $result = Invoke-StudioNative 'az' ($Arguments + @('--only-show-errors','--output','json'))
    if ([string]::IsNullOrWhiteSpace($result.output)) { return $null }
    try { return ConvertFrom-Json -InputObject $result.output -Depth 100 }
    catch { Stop-StudioOperation 'InvalidToolOutput' 'Azure CLI did not return valid JSON.' }
}

function Get-StudioSource {
    param([string] $ContainerName = 'sqldbcontainer', [switch] $Credential)
    if ($ContainerName -cne 'sqldbcontainer') { Stop-StudioOperation 'SourceNotApproved' 'Only sqldbcontainer is approved.' }
    $contextResult = Invoke-StudioNative 'docker' @('context','inspect')
    $context = @(ConvertFrom-Json -InputObject $contextResult.output -Depth 20)
    $hostAddress = if ($env:DOCKER_HOST) { $env:DOCKER_HOST } else { $context[0].Endpoints.docker.Host }
    if ($hostAddress -notmatch '^(npipe://|unix://|tcp://(localhost|127\.0\.0\.1|\[::1\]):\d+/?$)') {
        Stop-StudioOperation 'RemoteDockerNotApproved' 'The approved source must use a local Docker engine endpoint.'
    }
    $result = Invoke-StudioNative 'docker' @('inspect','--type','container',$ContainerName)
    $items = @(ConvertFrom-Json -InputObject $result.output -Depth 30)
    if ($items.Count -ne 1 -or $items[0].Name -cne '/sqldbcontainer' -or -not $items[0].State.Running) {
        Stop-StudioOperation 'SourceUnavailable' 'The approved source container is not running.'
    }
    $item = $items[0]
    $ports = @($item.NetworkSettings.Ports.'1433/tcp')
    $port = $ports | Where-Object { $_.HostIp -in @('127.0.0.1','::1','0.0.0.0','::') } | Select-Object -First 1
    if (-not $port -or $port.HostPort -notmatch '^\d{1,5}$' -or [int]$port.HostPort -notin 1..65535) {
        Stop-StudioOperation 'SourceEndpointUnavailable' 'No published local SQL port was discovered for the approved source.'
    }
    # Wildcard publishing is dialed only through loopback, never a request-supplied host.
    $endpoint = if ($port.HostIp -in @('::1','::')) { '[::1]' } else { '127.0.0.1' }
    $source = @{ name = 'sqldbcontainer'; image = [string]$item.Config.Image;
        endpoint = "$endpoint,$($port.HostPort)"; state = [string]$item.State.Status }
    if ($Credential) {
        $settings = @($item.Config.Env | Where-Object { $_.StartsWith('MSSQL_SA_PASSWORD=', [StringComparison]::Ordinal) })
        if ($settings.Count -ne 1 -or $settings[0].Length -le 18) {
            Stop-StudioOperation 'SourceCredentialUnavailable' 'The approved source has no unique SQL administrator environment setting.'
        }
        $source.password = [Net.NetworkCredential]::new('', $settings[0].Substring('MSSQL_SA_PASSWORD='.Length)).SecurePassword
        $source.password.MakeReadOnly()
        $settings = $null
    }
    $item = $null
    $items = $null
    $result = $null
    return $source
}

function Import-StudioSqlClient {
    if ('Microsoft.Data.SqlClient.SqlConnection' -as [type]) { return }
    # Mirror the already validated build-database.ps1 provider baseline, not a net10-only app DLL.
    try { Import-Module SqlServer -ErrorAction Stop }
    catch { Stop-StudioOperation 'MissingSqlClient' 'Install or repair the existing SqlServer PowerShell module; no software is installed automatically.' }
    if (-not ('Microsoft.Data.SqlClient.SqlConnection' -as [type])) {
        Stop-StudioOperation 'MissingSqlClient' 'A compatible Microsoft.Data.SqlClient provider is required.'
    }
}

function Open-StudioSourceConnection {
    param([hashtable] $Source, [string] $Database)
    Import-StudioSqlClient
    if ($Source.endpoint -notmatch '^(\[::1\]|127\.0\.0\.1|localhost),\d{1,5}$') {
        Stop-StudioOperation 'SourceNotLoopback' 'Source SQL connections must use the discovered loopback endpoint.'
    }
    $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Source.endpoint
    $builder['Initial Catalog'] = $Database
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Pooling'] = $false
    $builder['Connect Timeout'] = 15
    $builder['Application Name'] = 'SqlMigrationStudio'
    $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $connection.Credential = [Microsoft.Data.SqlClient.SqlCredential]::new('sa', $Source.password)
    try { $connection.Open(); return $connection }
    catch { $connection.Dispose(); Stop-StudioOperation 'SourceConnectionFailed' 'The approved loopback source connection failed; raw SQL diagnostics are withheld.' }
}

function Invoke-StudioQuery {
    param($Connection, [string] $Query, [hashtable] $Parameters = @{})
    Assert-StudioNotCancelled
    $command = $Connection.CreateCommand()
    try {
        $command.CommandText = $Query
        $command.CommandTimeout = 300
        foreach ($key in $Parameters.Keys) { [void]$command.Parameters.AddWithValue("@$key", $Parameters[$key]) }
        $reader = $command.ExecuteReader()
        try {
            $table = [Data.DataTable]::new()
            $table.Load($reader)
            return ,$table
        } finally { $reader.Dispose() }
    } catch { Stop-StudioOperation 'SqlCheckFailed' 'A maintained SQL check failed. Feature support, permissions, or connectivity must be reviewed locally; raw diagnostics are withheld.' }
    finally { $command.Dispose() }
}

function Assert-StudioSourceReadOnly {
    param($Connection)
    $state = Invoke-StudioQuery $Connection @'
SELECT is_read_only AS ReadOnly,
       HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'UNMASK') AS CanUnmask,
       HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CONTROL') AS IsOwner
FROM sys.databases WHERE database_id = DB_ID();
'@
    if ($state.Rows.Count -ne 1 -or -not [bool]$state.Rows[0].ReadOnly) {
        Stop-StudioOperation 'SourceNotReadOnly' 'Export blocked: the source must already be READ_ONLY under separately approved operational write quiescence. Stopping one app or checking a box is not proof. This engine never changes source state.'
    }
    if ($state.Rows[0].CanUnmask -ne 1 -or $state.Rows[0].IsOwner -ne 1) {
        Stop-StudioOperation 'SourcePrivilegeRequired' 'Export requires an owner with database UNMASK so stored contact values are preserved.'
    }
}

function Get-StudioSubscriptions {
    param([System.Collections.IDictionary] $Config)
    if (-not $Config.Contains('tenantId')) { Stop-StudioOperation 'TenantRequired' 'Select a tenant first.' }
    $accounts = @(Invoke-StudioAz @('account','list','--all'))
    return @($accounts | Where-Object { $_.tenantId -eq $Config.tenantId -and $_.state -eq 'Enabled' } |
        ForEach-Object { @{ id = $_.id; name = $_.name; tenantId = $_.tenantId } })
}

function Assert-StudioAzureContext {
    param([System.Collections.IDictionary] $Config)
    if (-not $Config.Contains('subscriptionId') -or -not $Config.Contains('tenantId')) {
        Stop-StudioOperation 'AzureSelectionRequired' 'Select an authenticated tenant and subscription first.'
    }
    $account = Invoke-StudioAz @('account','show','--subscription',$Config.subscriptionId)
    if ($account.tenantId -ne $Config.tenantId -or $account.id -ne $Config.subscriptionId -or $account.state -ne 'Enabled') {
        Stop-StudioOperation 'TenantMismatch' 'The selected subscription does not belong to the authenticated selected tenant.'
    }
}

function Get-StudioIdentity {
    param([System.Collections.IDictionary] $Config)
    Assert-StudioAzureContext $Config
    $token = Invoke-StudioAz @('account','get-access-token','--subscription',$Config.subscriptionId,
        '--resource','https://graph.microsoft.com/')
    try {
        $parts = $token.accessToken.Split('.')
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        if ($claims.tid -ne $Config.tenantId) { Stop-StudioOperation 'TenantMismatch' 'Azure returned a token for the wrong tenant.' }
        $me = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName' `
            -Headers @{ Authorization = "Bearer $($token.accessToken)" } -TimeoutSec 30
        if ($me.id -ne $claims.oid) { Stop-StudioOperation 'IdentityMismatch' 'The signed-in Graph identity does not match the selected tenant token.' }
        return @{ id = $me.id; name = $me.displayName; userPrincipalName = $me.userPrincipalName }
    } catch [StudioBlockedException] { throw }
    catch { Stop-StudioOperation 'IdentityUnavailable' 'Unable to confirm a signed-in user in the selected tenant. Sign in to that tenant and grant Graph User.Read.' }
    finally { $token = $null; $claims = $null }
}

function Get-StudioSqlPackage {
    $candidates = @()
    if ($env:STUDIO_SQLPACKAGE_PATH) { $candidates += $env:STUDIO_SQLPACKAGE_PATH }
    $command = Get-Command sqlpackage -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates += $command.Source }
    $candidates += @(
        (Join-Path $env:ProgramFiles 'SqlPackage\sqlpackage.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\SqlPackage\sqlpackage.exe'),
        (Join-Path $env:USERPROFILE '.dotnet\tools\sqlpackage.exe'))
    foreach ($path in $candidates) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $version = Invoke-StudioNative $path @('/Version') -AllowFailure
        $match = [regex]::Match($version.output, '\b\d+\.\d+\.\d+\.\d+\b')
        if ($version.exitCode -ne 0 -or -not $match.Success) { continue }
        $dac = Join-Path (Split-Path $path) 'Microsoft.SqlServer.Dac.dll'
        if (([version]$match.Value) -lt [version]'170.5.96.0') { continue }
        if (-not (Test-Path -LiteralPath $dac)) { continue }
        return @{ path = [IO.Path]::GetFullPath($path); directory = Split-Path $path; version = $match.Value }
    }
    Stop-StudioOperation 'SqlPackageRequired' 'SqlPackage 170.5.96.0 or later with adjacent .NET DacFx assemblies is required. Set STUDIO_SQLPACKAGE_PATH to the installed executable. No installation was attempted.'
}

function Get-StudioPreflight {
    param([System.Collections.IDictionary] $Config)
    $checks = [Collections.Generic.List[object]]::new()
    foreach ($tool in @(@{name='Docker';file='docker';args=@('version','--format','{{.Server.Version}}')},
        @{name='Azure CLI';file='az';args=@('version')},
        @{name='Copilot';file='copilot';args=@('--version')})) {
        try {
            $result = Invoke-StudioNative $tool.file $tool.args
            $version = [regex]::Match($result.output, '\b\d+\.\d+(?:\.\d+)?\b').Value
            $checks.Add(@{ name=$tool.name; state='ready'; version=$version; message='Installed and callable.' })
        } catch { $checks.Add(@{ name=$tool.name; state='blocked'; message='Unavailable or not callable. No software was installed.' }) }
    }
    foreach ($name in @('SqlPackage','SQL provider','Azure authentication','Source')) {
        try {
            $version = $null
            switch ($name) {
                'SqlPackage' { $version = (Get-StudioSqlPackage).version }
                'SQL provider' { Import-StudioSqlClient; $version = [Microsoft.Data.SqlClient.SqlConnection].Assembly.GetName().Version.ToString() }
                'Azure authentication' {
                    if ($Config.Contains('subscriptionId')) { Assert-StudioAzureContext $Config }
                    else { [void](Invoke-StudioAz @('account','show')) }
                }
                'Source' { [void](Get-StudioSource) }
            }
            $checks.Add(@{name=$name;state='ready';version=$version;message='Read-only readiness check passed.'})
        } catch { $checks.Add(@{name=$name;state='blocked';message=(Get-StudioSafeError $_).message}) }
    }
    if ($Config.Contains('sourceDatabase')) {
        $source = $null; $connection = $null
        try {
            $source = Get-StudioSource -Credential
            $connection = Open-StudioSourceConnection $source $Config.sourceDatabase
            Assert-StudioSourceReadOnly $connection
            $checks.Add(@{name='Source export consistency';state='ready';message='Source is already READ_ONLY with owner and UNMASK privilege; scripts do not change operational state.'})
        } catch { $checks.Add(@{name='Source export consistency';state='blocked';message=(Get-StudioSafeError $_).message}) }
        finally {
            if ($connection) { $connection.Dispose() }
            if ($source) { $source.password.Dispose() }
        }
    } else {
        $checks.Add(@{name='Source export consistency';state='unknown';message='Select a database. Export requires separately approved existing READ_ONLY; writer acknowledgment alone is not proof.'})
    }
    return @{ ready = @($checks | Where-Object state -ne 'ready').Count -eq 0;
        capabilities = @($checks.ToArray() | ForEach-Object {
            $detail = $_.message
            if ($_.Contains('version') -and $_.version) { $detail = "$($_.version). $detail" }
            @{name=$_.name;state=$_.state;detail=$detail}
        });
        limitations = @('Copilot account authentication is verified by the SDK, not by CLI version.',
            'Export requires separately approved source READ_ONLY. Target firewall access must already be configured.',
            'Preview feature fidelity is not proven until real export, import, and verification succeed.') }
}

function Assert-StudioFreeDatabase {
    param($Database)
    if ($Database.useFreeLimit -ne $true -or $Database.freeLimitExhaustionBehavior -cne 'AutoPause' -or
        $Database.sku.tier -ne 'GeneralPurpose' -or $Database.sku.name -ne 'GP_S_Gen5' -or
        [int]$Database.sku.capacity -ne 2 -or [long]$Database.maxSizeBytes -gt 32GB) {
        Stop-StudioOperation 'FreeProtectionRequired' 'Target must be the approved General Purpose serverless 2-vCore free database, at most 32 GiB, with useFreeLimit=true and AutoPause. Paid fallback is forbidden.'
    }
}

function Open-StudioTargetConnection {
    param([System.Collections.IDictionary] $Config)
    Import-StudioSqlClient
    Assert-StudioAzureContext $Config
    $token = Invoke-StudioAz @('account','get-access-token','--subscription',$Config.subscriptionId,
        '--resource','https://database.windows.net/')
    $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = "tcp:$($Config.serverName).database.windows.net,1433"
    $builder['Initial Catalog'] = $Config.targetDatabase
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $false
    $builder['Pooling'] = $false
    $builder['Connect Timeout'] = 30
    $builder['Application Name'] = 'SqlMigrationStudio'
    $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $connection.AccessToken = $token.accessToken
    $token = $null
    try { $connection.Open(); return $connection }
    catch { $connection.Dispose(); Stop-StudioOperation 'TargetConnectionFailed' 'Target Entra connection failed. Check selected-tenant admin and existing narrowly scoped client firewall access. This engine never opens a firewall.' }
}

function Assert-StudioEmptyTarget {
    param($Connection)
    $table = Invoke-StudioQuery $Connection @'
SELECT COUNT_BIG(*) AS ObjectCount FROM sys.objects
WHERE is_ms_shipped = 0 AND type NOT IN ('S','IT');
'@
    if ([long]$table.Rows[0].ObjectCount -ne 0) {
        Stop-StudioOperation 'TargetNotEmpty' 'Target contains user objects. It will not be cleared, overwritten, recreated, or imported into.'
    }
}

function Get-StudioTargetDatabase {
    param([System.Collections.IDictionary] $Config)
    return Invoke-StudioAz @('sql','db','show','--subscription',$Config.subscriptionId,
        '--resource-group',$Config.resourceGroup,'--server',$Config.serverName,'--name',$Config.targetDatabase)
}

function New-StudioTarget {
    param([System.Collections.IDictionary] $Config, $Identity)
    $sub = @('--subscription',$Config.subscriptionId)
    $groups = @(Invoke-StudioAz (@('group','list') + $sub))
    $group = $groups | Where-Object name -eq $Config.resourceGroup | Select-Object -First 1
    if (-not $group) {
        if (-not $Config.createResourceGroup) { Stop-StudioOperation 'ResourceGroupMissing' 'The selected group does not exist and creation was not approved.' }
        [void](Invoke-StudioAz (@('group','create','--name',$Config.resourceGroup,'--location',$Config.region) + $sub))
    } elseif ($Config.createResourceGroup) {
        Stop-StudioOperation 'ResourceConflict' 'A group marked for creation already exists. Refresh and reapprove reuse.'
    }
    $servers = @(Invoke-StudioAz (@('sql','server','list','--resource-group',$Config.resourceGroup) + $sub))
    $server = $servers | Where-Object name -eq $Config.serverName | Select-Object -First 1
    if ($server) {
        if ($Config.createServer) { Stop-StudioOperation 'ResourceConflict' 'A server marked for creation already exists. Refresh and reapprove reuse.' }
        if ($server.location -ne $Config.region) { Stop-StudioOperation 'RegionMismatch' 'The existing server is in a different region.' }
        $admins = @(Invoke-StudioAz (@('sql','server','ad-admin','list','--resource-group',$Config.resourceGroup,'--server',$Config.serverName) + $sub))
        if (@($admins | Where-Object { $_.sid -eq $Identity.id -and $_.tenantId -eq $Config.tenantId }).Count -ne 1) {
            Stop-StudioOperation 'ExistingAdminNotApproved' 'Existing server administrator does not match the confirmed tenant user. Administrator/authentication settings will not be changed.'
        }
    } else {
        if (-not $Config.createServer) { Stop-StudioOperation 'ServerMissing' 'The selected server does not exist and creation was not approved.' }
        [void](Invoke-StudioAz (@('sql','server','create','--resource-group',$Config.resourceGroup,
            '--name',$Config.serverName,'--location',$Config.region,'--enable-ad-only-auth',
            '--external-admin-principal-type','User','--external-admin-name',$Identity.userPrincipalName,
            '--external-admin-sid',$Identity.id) + $sub))
    }
    $databases = @(Invoke-StudioAz (@('sql','db','list','--resource-group',$Config.resourceGroup,'--server',$Config.serverName) + $sub))
    if (@($databases | Where-Object name -eq $Config.targetDatabase).Count -gt 0) {
        Stop-StudioOperation 'TargetAlreadyExists' 'The target database already exists. This migration will not adopt or overwrite a database from another or interrupted run.'
    }
    $editions = @(Invoke-StudioAz (@('sql','db','list-editions','--location',$Config.region,'--available',
        '--edition','GeneralPurpose','--service-objective','GP_S_Gen5_2') + $sub))
    if ($editions.Count -eq 0) { Stop-StudioOperation 'SkuUnavailable' 'The approved free serverless SKU is unavailable in this region/subscription.' }
    [void](Invoke-StudioAz (@('sql','db','create','--resource-group',$Config.resourceGroup,'--server',$Config.serverName,
        '--name',$Config.targetDatabase,'--edition','GeneralPurpose','--compute-model','Serverless',
        '--family','Gen5','--capacity','2','--min-capacity','0.5','--max-size','32GB',
        '--backup-storage-redundancy','Local','--use-free-limit','true','--free-limit-exhaustion-behavior','AutoPause') + $sub))
    Assert-StudioFreeDatabase (Get-StudioTargetDatabase $Config)
}

function Get-StudioSafeError {
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($exception -and $exception -isnot [StudioBlockedException]) { $exception = $exception.InnerException }
    if ($exception) { return @{code=$exception.Code;message=$exception.Message} }
    return @{code='OperationFailed';message='Operation failed. Raw tool/SQL diagnostics are withheld because they can contain credentials or private data. Partial target state is retained; re-inspect before retrying.'}
}

Export-ModuleMember -Function *-Studio*
