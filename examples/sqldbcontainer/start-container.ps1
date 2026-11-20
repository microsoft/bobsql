#requires -Version 7.0
<#
.SYNOPSIS
Pulls and starts the Azure SQL development container with persistent storage.
.DESCRIPTION
Requires -AcceptEula for first creation. Prompts securely for the initial SA
password, unless -SaPassword is supplied as a SecureString. Reuses matching
containers without removing or recreating them. SQL readiness uses the initial
SA password stored in the container environment, never printed by this script.
Use -RepairLocalhost to replace an older loopback-only container definition while
retaining its database volume and its stopped original container for rollback.
Port publishing uses Docker's standard host binding, including network interfaces.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_.-]+$')]
    [string]$ContainerName = 'sqldbcontainer',
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_.-]+$')]
    [string]$VolumeName = 'sqldbcontainer-public-data',
    [ValidateRange(1, 65535)]
    [int]$Port = 14332,
    [ValidateNotNullOrEmpty()]
    [string]$Image = 'mcr.microsoft.com/mssql/azure-sql-db-server:latest',
    [Security.SecureString]$SaPassword,
    [switch]$AcceptEula,
    [switch]$StartDockerDesktop,
    [switch]$SkipPull,
    [switch]$RepairLocalhost,
    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-DockerChecked {
    param([string[]]$Arguments)
    $output = docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host ($output -join [Environment]::NewLine)
        throw "Docker '$($Arguments[0])' failed (exit code $LASTEXITCODE). See Docker output above."
    }
    $output
}

& (Join-Path $PSScriptRoot 'preflight.ps1') -DockerOnly -StartDockerDesktop:$StartDockerDesktop
$existing = Invoke-DockerChecked -Arguments @('ps', '-a', '--filter', "name=^/$ContainerName$", '--format', '{{.ID}}')

if ($existing) {
    $container = (Invoke-DockerChecked -Arguments @('inspect', $ContainerName) | ConvertFrom-Json)[0]
    $binding = @($container.HostConfig.PortBindings.'1433/tcp')
    $ipv4 = @($binding | Where-Object { $_.HostIp -eq '127.0.0.1' -and $_.HostPort -eq "$Port" })
    $ipv6 = @($binding | Where-Object { $_.HostIp -eq '::1' -and $_.HostPort -eq "$Port" })
    $standardIpv4 = @($binding | Where-Object { $_.HostIp -in @('', '0.0.0.0') -and $_.HostPort -eq "$Port" })
    $standardIpv6 = @($binding | Where-Object { $_.HostIp -eq '::' -and $_.HostPort -eq "$Port" })
    $standardBinding = $standardIpv4.Count -eq 1 -and $standardIpv6.Count -le 1 -and
        $binding.Count -eq (1 + $standardIpv6.Count)
    $loopbackBinding = $ipv4.Count -eq 1 -and $ipv6.Count -le 1 -and
        $binding.Count -eq (1 + $ipv6.Count)
    $mount = @($container.Mounts | Where-Object { $_.Destination -eq '/var/opt/mssql' })
    if ($container.Config.Labels.'bwsql.project' -ne 'sqldbcontainer' -or
        $container.Config.Image -ne $Image -or
        (-not $standardBinding -and -not $loopbackBinding) -or
        $mount.Count -ne 1 -or $mount[0].Type -ne 'volume' -or $mount[0].Name -ne $VolumeName) {
        throw "Container '$ContainerName' does not match this setup's image, label, port, or volume. Nothing was replaced. Use its original settings or choose a different container, volume, and port."
    }
    if ($container.State.Status -notin @('running', 'exited', 'created')) {
        throw "Container '$ContainerName' is '$($container.State.Status)'. Resolve that state explicitly before rerunning."
    }
    if ($SaPassword) {
        throw '-SaPassword only sets the initial password for a new container; it cannot change an existing SQL login.'
    }
    if (-not $standardBinding -and -not $RepairLocalhost) {
        throw "Container '$ContainerName' has an old loopback-only binding. Rerun with -SkipPull -RepairLocalhost to use standard Docker publishing on host interfaces while preserving the database volume."
    }
} elseif (-not $AcceptEula) {
    throw 'First creation requires -AcceptEula after reviewing the image license terms. No container was created.'
}

if (-not $SkipPull) {
    & (Join-Path $PSScriptRoot 'pull-container.ps1') -Image $Image
}
$imageId = Invoke-DockerChecked -Arguments @('image', 'inspect', '--format', '{{.Id}}', $Image)

if ($existing -and -not $standardBinding -and $RepairLocalhost) {
    if ($container.Image -ne $imageId) {
        throw 'The image reference has changed since this container was created. Localhost repair will not also upgrade SQL. Restore the original image reference before repairing.'
    }
    $passwordSetting = @($container.Config.Env | Where-Object { $_.StartsWith('MSSQL_SA_PASSWORD=') })
    if ($passwordSetting.Count -ne 1 -or $container.Config.Env -notcontains 'ACCEPT_EULA=Y') {
        throw 'Cannot reuse the original SQL password and accepted license settings. No container changes were made.'
    }
    $initialPassword = [Net.NetworkCredential]::new('', $passwordSetting[0].Substring('MSSQL_SA_PASSWORD='.Length)).SecurePassword
    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $backupName = "$ContainerName-before-localhost-$suffix"
    $renamed = $false
    $repaired = $false
    try {
        if ($container.State.Running) {
            Invoke-DockerChecked -Arguments @('stop', '--timeout', '30', $ContainerName) | Out-Host
        }
        Invoke-DockerChecked -Arguments @('rename', $ContainerName, $backupName) | Out-Host
        $renamed = $true
        & $PSCommandPath -SkipPull -AcceptEula -SaPassword $initialPassword -Image $Image `
            -ContainerName $ContainerName -VolumeName $VolumeName -Port $Port -TimeoutSeconds $TimeoutSeconds
        $repaired = $true
        Write-Host "Localhost repair completed. Data volume '$VolumeName' retained. Original container retained, stopped, as '$backupName'."
    } finally {
        if (-not $repaired) {
            if ($renamed) {
                $replacement = Invoke-DockerChecked -Arguments @('ps', '-a', '--filter', "name=^/$ContainerName$", '--format', '{{.ID}}')
                if ($replacement) {
                    Invoke-DockerChecked -Arguments @('stop', '--timeout', '30', $ContainerName) | Out-Host
                    Invoke-DockerChecked -Arguments @('rename', $ContainerName, "$ContainerName-failed-localhost-$suffix") | Out-Host
                }
                Invoke-DockerChecked -Arguments @('rename', $backupName, $ContainerName) | Out-Host
            }
            if ($container.State.Running) {
                Invoke-DockerChecked -Arguments @('start', $ContainerName) | Out-Host
            }
            Write-Warning 'Localhost repair failed. The original container was restored; any replacement container was retained, stopped, for diagnosis.'
        }
    }
    return
}

if ($existing) {
    if ($container.Image -ne $imageId) {
        Write-Warning 'The local image tag now resolves to a different build. Keeping the existing container and its data; no automatic upgrade was performed.'
    }
    if (-not $container.State.Running) {
        Invoke-DockerChecked -Arguments @('start', $ContainerName) | Out-Host
    }
} else {
    if (-not $SaPassword) {
        $SaPassword = Read-Host 'Initial SQL sa password (not the registry password)' -AsSecureString
    }
    if ($SaPassword.Length -eq 0) {
        throw 'The initial SQL sa password cannot be empty.'
    }
    $previousPassword = [Environment]::GetEnvironmentVariable('MSSQL_SA_PASSWORD', 'Process')
    try {
        $env:MSSQL_SA_PASSWORD = [Net.NetworkCredential]::new('', $SaPassword).Password
        Invoke-DockerChecked -Arguments @(
            'run', '--detach', '--name', $ContainerName,
            '--label', 'bwsql.project=sqldbcontainer',
            '--publish', "${Port}:1433",
            '--mount', "type=volume,source=$VolumeName,target=/var/opt/mssql",
            '--env', 'ACCEPT_EULA=Y',
            '--env', 'MSSQL_SA_PASSWORD',
            $Image
        ) | Out-Host
    } finally {
        [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $previousPassword, 'Process')
    }
}

$sqlcmdPath = Invoke-DockerChecked -Arguments @(
    'exec', $ContainerName, 'sh', '-c',
    'if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then echo /opt/mssql-tools18/bin/sqlcmd; elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then echo /opt/mssql-tools/bin/sqlcmd; else echo "No supported sqlcmd found in the image." >&2; exit 1; fi'
)
$probe = 'export SQLCMDPASSWORD="$MSSQL_SA_PASSWORD"; exec "$1" -S localhost -U sa -C -b -l 3 -t 3 -Q "SET NOCOUNT ON; SELECT 1;"'
$timer = [Diagnostics.Stopwatch]::StartNew()
$result = $null
Write-Host "Waiting for SQL in '$ContainerName'..."
do {
    $state = Invoke-DockerChecked -Arguments @('inspect', '--format', '{{.State.Status}}', $ContainerName)
    if ($state -ne 'running') {
        if ($result) {
            Write-Host ($result -join [Environment]::NewLine)
        }
        throw "Container '$ContainerName' is '$state'. Inspect it with: docker logs --tail 80 $ContainerName"
    }
    $result = docker exec $ContainerName sh -c $probe sh $sqlcmdPath 2>&1
    $probeExitCode = $LASTEXITCODE
    if ($probeExitCode -eq 0) {
        Write-Host "SQL is ready inside the container. Host endpoint: localhost,$Port (SQL authentication, user sa). Data volume: $VolumeName."
        Write-Host 'Port is published on host interfaces; network access is subject to the host firewall.'
        Write-Host 'SQL readiness passed; JSON, vector search, regex masking, and cloud portability are not yet verified.'
        return
    }
    if ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 2
    }
} while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)

Write-Host ($result -join [Environment]::NewLine)
throw "SQL did not become ready within $TimeoutSeconds seconds. Container and data were preserved. Inspect: docker logs --tail 80 $ContainerName"
