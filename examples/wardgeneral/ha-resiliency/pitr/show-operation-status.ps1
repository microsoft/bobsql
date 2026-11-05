<#
.SYNOPSIS
    Show the recent PITR management operation from sys.dm_operation_status.

.DESCRIPTION
    Connects to master with passwordless authentication and polls the newest
    operation for the named restored database until it completes, fails, is
    cancelled, or reaches the bounded timeout. Azure retains these rows for
    approximately one hour.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RestoredDatabase,
    [string] $Server,
    [string] $SqlCmd,
    [ValidateRange(1, 1440)]
    [int] $TimeoutMinutes = 60,
    [ValidateRange(1, 300)]
    [int] $PollIntervalSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No Ward General server is configured.'
}
if ($RestoredDatabase -notmatch '^wardgeneral-pitr-') {
    throw "Operation target '$RestoredDatabase' is outside this demo. High Availability and Resiliency restored database names must start with 'wardgeneral-pitr-'."
}

$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sqlcmdPath) {
    throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd'
}

$script = Join-Path $PSScriptRoot 'operation-status.sql'
$deadline = [DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)
$lastState = $null

Write-Host "Waiting up to $TimeoutMinutes minute(s) for PITR target '$RestoredDatabase'."
do {
    $output = & $sqlcmdPath `
        -S $Server `
        -d master `
        -G `
        -b `
        -h -1 `
        -W `
        -y 0 `
        -w 65535 `
        -i $script `
        -v "RestoredDatabase=$RestoredDatabase"
    if ($LASTEXITCODE -ne 0) {
        throw "Operation-status query failed with exit code $LASTEXITCODE."
    }

    $json = ($output -join '').Trim()
    if ($json -and $json -ne 'NULL') {
        $status = $json | ConvertFrom-Json
        if ($status.state_desc -ne $lastState) {
            Write-Host ''
            $status | Format-List
            $lastState = $status.state_desc
        }
        else {
            Write-Host ("{0:u} state={1} percent={2}" -f [DateTime]::UtcNow, $status.state_desc, $status.percent_complete)
        }

        if ($status.state_desc -eq 'COMPLETED') {
            Write-Host "RestoreOperation=COMPLETED"
            return
        }
        if ($status.state_desc -in @('FAILED', 'CANCELLED')) {
            throw "Restore operation ended in state '$($status.state_desc)': error $($status.error_code) $($status.error_desc)"
        }
    }
    else {
        Write-Host ("{0:u} state=NOT_FOUND" -f [DateTime]::UtcNow)
    }

    if ([DateTimeOffset]::UtcNow -ge $deadline) {
        throw "Restore operation did not complete within $TimeoutMinutes minute(s). Last state: $($lastState ?? 'NOT_FOUND')."
    }
    Start-Sleep -Seconds $PollIntervalSeconds
} while ($true)
