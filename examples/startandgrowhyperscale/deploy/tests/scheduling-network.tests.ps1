[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\07-deploy-scheduling.ps1'
$permissionsPath = Join-Path $PSScriptRoot '..\..\sql\03-app-permissions.sql'
$names = @('caldova-scheduling', 'northbrook-scheduling', 'ridgeview-scheduling')
$script:files = [System.Collections.Generic.List[object]]::new()
$script:lookupDatabases = [System.Collections.Generic.List[string]]::new()
$script:loginSid = '0x00112233445566778899AABBCCDDEEFF'
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Import-Module {
    [CmdletBinding()]
    param([string]$Name)
    Assert-True ($Name -eq 'SqlServer') 'Only the mocked SqlServer module may be imported'
}

function az {
    $arguments = @($args)
    $global:LASTEXITCODE = 0
    switch ($arguments[0..2] -join ' ') {
        'account get-access-token --subscription' { return '{"accessToken":"offline-token"}' }
        'sql elastic-pool show' { return '{"id":"test-pool"}' }
        'sql db show' { return '{"elasticPoolId":"test-pool","status":"Online"}' }
        default { throw "Unexpected Azure command: $($arguments -join ' ')" }
    }
}

function Invoke-Sqlcmd {
    [CmdletBinding()]
    param(
        [string]$ServerInstance, [string]$Database, [string]$AccessToken,
        [string]$Query, [string]$InputFile, [string[]]$Variable = @(),
        [int]$ConnectionTimeout, [int]$QueryTimeout, [string]$Encrypt,
        [switch]$AbortOnError, [bool]$OutputSqlErrors
    )
    Assert-True ($AccessToken -eq 'offline-token') 'SQL must use the mocked CLI token'
    Assert-True ($Encrypt -eq 'Mandatory' -and $AbortOnError) 'SQL failure and encryption settings must be preserved'
    if ($Query) {
        Assert-True ($Database -eq 'master' -and $Query.Contains('sys.server_principals')) 'Resolve the login SID only in master'
        Assert-True ($files.Count -eq 0) 'Resolve the login before any setup file executes'
        $lookupDatabases.Add($Database)
        if ($null -ne $loginSid) { return [pscustomobject]@{ AppLoginSid = $loginSid } }
        return
    }
    $files.Add([pscustomobject]@{
        Database = $Database; File = [IO.Path]::GetFileName($InputFile); Variables = @($Variable)
    })
}

$overrides = @{
    AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000000'
    CALDOVA_NETWORK_APP_NAME = 'app-caldova-network-test'
    CALDOVA_NETWORK_SQL_SERVER = 'sql-caldova-network-test'
}
$previous = @{}
try {
    foreach ($key in $overrides.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $overrides[$key], 'Process')
    }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) 'Deployment script must parse'
    $passed++

    & $scriptPath -Phase Network | Out-Null
    Assert-True ($lookupDatabases.Count -eq 1 -and $files.Count -eq 4) 'Network setup requires one lookup, one view, and three permissions files'
    Assert-True ($files[0].Database -eq $names[0] -and $files[0].File -eq '02-network-view.sql') 'The view belongs only in Caldova'
    $passed++
    for ($i = 0; $i -lt $names.Count; $i++) {
        $call = $files[$i + 1]
        Assert-True ($call.Database -eq $names[$i] -and $call.File -eq '03-app-permissions.sql') 'Grant only in the three scheduling databases'
        Assert-True ($call.Variables.Count -eq 2 -and $call.Variables[0] -ceq "AppLoginSid=$loginSid" -and
            $call.Variables[1] -ceq 'AppName=app-caldova-network-test') 'Every permissions file receives the exact master login SID and configured app name'
        $passed++
    }

    foreach ($invalid in @($null, '', '0x', '0xABC', '0xGG', '0x01;SELECT 1', ('0x' + '01' * 86), '0x01', ('0x' + '01' * 18))) {
        $script:files.Clear()
        $script:lookupDatabases.Clear()
        $script:loginSid = $invalid
        $failure = $null
        try { & $scriptPath -Phase Network | Out-Null } catch { $failure = $_.Exception.Message }
        Assert-True ($failure -like '*valid SID*' -and $files.Count -eq 0) 'Missing or invalid login SID must stop before any SQL setup file'
        $passed++
    }

    $script:files.Clear()
    $script:lookupDatabases.Clear()
    & $scriptPath -Phase Schema | Out-Null
    Assert-True ($lookupDatabases.Count -eq 0 -and $files.Count -eq 4) 'Schema setup must not introduce a network-login lookup'
    Assert-True ($files[0].Database -eq 'master' -and $files[0].File -eq '00-app-login.sql') 'Existing schema setup still creates the master login first'
    Assert-True ($files[0].Variables.Count -eq 1 -and $files[0].Variables[0] -ceq 'AppName=app-caldova-network-test') 'The master login receives the configured app name, not a tracked literal'
    Assert-True (@($files | Select-Object -Skip 1 | Where-Object { $_.Variables.Count -gt 0 }).Count -eq 0) 'Existing schema files require no new SQLCMD variables'
    $passed++

    $permissions = Get-Content -LiteralPath $permissionsPath -Raw
    Assert-True ($permissions.Contains('DECLARE @AppLoginSid varbinary(85) = $(AppLoginSid);')) 'SQL receives the validated binary login SID'
    Assert-True ($permissions.Contains('sid <> @AppLoginSid + 0xAADE') -and
        $permissions.Contains("type NOT IN ('E', 'X')") -and $permissions.Contains('THROW 50002')) 'Require the expected Entra identity and login-based SID suffix without remapping users'
    Assert-True ($permissions.Contains('DATALENGTH(@AppLoginSid) <> 16')) 'The expected Entra login SID must be sixteen bytes'
    Assert-True ($permissions -notmatch 'SUSER_SID\s*\(') 'User databases must not invoke unsupported named SUSER_SID'
    Assert-True ($permissions.Contains('CREATE USER [$(AppName)] FROM LOGIN [$(AppName)]')) 'Preserve login-mapped users, not contained-user substitutes'
    $login = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\sql\00-app-login.sql') -Raw
    Assert-True ($login.Contains('CREATE LOGIN [$(AppName)] FROM EXTERNAL PROVIDER')) 'The master login uses the SQLCMD app name variable'
    $passed++

    $script:files.Clear()
    $script:lookupDatabases.Clear()
    $script:loginSid = '0x00112233445566778899AABBCCDDEEFF'
    [Environment]::SetEnvironmentVariable('CALDOVA_NETWORK_APP_NAME', "app-caldova-network-test'];DROP", 'Process')
    $failure = $null
    try { & $scriptPath -Phase Schema | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-True ($failure -like '*SQLCMD variable AppName*' -and $files.Count -eq 0) 'An unsafe app name stops before any SQL file runs'
    $passed++
    Write-Host "PASS: $passed network-setup checks (mocked Azure and SQL only)."
}
finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
