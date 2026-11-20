#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Export','Import')][string] $Action,
    [Parameter(Mandatory)][string] $InputFile
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'Studio.Engine.psm1') -DisableNameChecking
$source = $null
$sourceConnection = $null
$targetConnection = $null
$package = $null
try {
    Assert-StudioProtectedFile $InputFile
    $config = Get-Content -LiteralPath $InputFile -Raw | ConvertFrom-Json -AsHashtable
    Assert-StudioConfiguration $config 'Migrate'
    Set-StudioRunContext $config.runDirectory
    Assert-StudioNotCancelled
    $tool = Get-StudioSqlPackage
    # An isolated process prevents SqlServer module DacFx/provider version conflicts.
    # Secrets are obtained here in memory, never passed on a command line or written to disk.
    $directory = $tool.directory
    $resolver = [System.ResolveEventHandler] {
        param($sender, $eventArgs)
        $name = [Reflection.AssemblyName]::new($eventArgs.Name).Name
        $path = Join-Path $directory "$name.dll"
        if (Test-Path -LiteralPath $path) { return [Reflection.Assembly]::LoadFrom($path) }
        return $null
    }.GetNewClosure()
    [AppDomain]::CurrentDomain.add_AssemblyResolve($resolver)
    foreach ($assembly in @('Microsoft.Data.SqlClient.dll','Microsoft.SqlServer.Dac.dll')) {
        [void][Reflection.Assembly]::LoadFrom((Join-Path $directory $assembly))
    }
    if (-not ('Microsoft.SqlServer.Dac.DacServices' -as [type])) {
        Stop-StudioOperation 'IncompatibleDacFx' 'The installed DacFx runtime cannot load in this PowerShell version.'
    }
    $scratch = Join-Path $config.runDirectory 'dac-work'
    Protect-StudioDirectory $scratch
    $env:TEMP = $scratch
    $env:TMP = $scratch
    $bacpac = Join-Path $config.runDirectory 'source.bacpac'
    if ($Action -eq 'Export') {
        if (Test-Path -LiteralPath $bacpac) { Stop-StudioOperation 'ArtifactAlreadyExists' 'An export artifact already exists; it will not be overwritten.' }
        $source = Get-StudioSource -Credential
        $sourceConnection = Open-StudioSourceConnection $source $config.sourceDatabase
        Assert-StudioSourceReadOnly $sourceConnection
        $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($sourceConnection.ConnectionString)
        $builder['User ID'] = 'sa'
        $service = [Microsoft.SqlServer.Dac.DacServices]::new($builder.ConnectionString,$source.password)
        $options = [Microsoft.SqlServer.Dac.DacExportOptions]::new()
        $options.VerifyExtraction = $true
        $options.CommandTimeout = 300
        $options.LongRunningCommandTimeout = 3600
        $options.HashObjectNamesInLogs = $true
        $options.TempDirectoryForTableData = $scratch
        $service.ExportBacpac($bacpac,$config.sourceDatabase,$options,$null,[Threading.CancellationToken]::None)
        Assert-StudioSourceReadOnly $sourceConnection
    } else {
        if (-not (Test-Path -LiteralPath $bacpac -PathType Leaf)) { Stop-StudioOperation 'ExportMissing' 'A completed protected BACPAC is required.' }
        Assert-StudioFreeDatabase (Get-StudioTargetDatabase $config)
        $targetConnection = Open-StudioTargetConnection $config
        Assert-StudioEmptyTarget $targetConnection
        Add-Type -ReferencedAssemblies (Join-Path $directory 'Microsoft.SqlServer.Dac.dll') -TypeDefinition @'
using Microsoft.SqlServer.Dac;
namespace SqlMigrationStudio {
    public sealed class TokenProvider : IUniversalAuthProvider {
        private readonly string token;
        public TokenProvider(string token) { this.token = token; }
        public string GetValidAccessToken() { return token; }
    }
}
'@
        $provider = [SqlMigrationStudio.TokenProvider]::new($targetConnection.AccessToken)
        $service = [Microsoft.SqlServer.Dac.DacServices]::new($targetConnection.ConnectionString,$provider)
        $package = [Microsoft.SqlServer.Dac.BacPackage]::Load($bacpac)
        $options = [Microsoft.SqlServer.Dac.DacImportOptions]::new()
        $options.CommandTimeout = 300
        $options.LongRunningCommandTimeout = 3600
        $options.HashObjectNamesInLogs = $true
        $options.PreserveIdentityLastValues = $true
        $service.ImportBacpac($package,$config.targetDatabase,$options,[Threading.CancellationToken]::None)
        Assert-StudioFreeDatabase (Get-StudioTargetDatabase $config)
    }
    Assert-StudioNotCancelled
    [Console]::Out.WriteLine('{"success":true}')
    exit 0
} catch {
    $safe = Get-StudioSafeError $_
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject @{success=$false;safeError=$safe.message;code=$safe.code} -Compress))
    exit 1
} finally {
    if ($package) { $package.Dispose() }
    if ($targetConnection) { $targetConnection.Dispose() }
    if ($sourceConnection) { $sourceConnection.Dispose() }
    if ($source) { $source.password.Dispose() }
}
