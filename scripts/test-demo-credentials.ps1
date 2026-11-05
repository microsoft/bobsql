$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('bobsql-credential-test-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
$names = @('SQLCMDPASSWORD', 'MSSQL_SA_PASSWORD', 'SQLLINUXPASSWORD', 'SqlLoginPassword', 'EXPECTED_DEMO_INPUT', 'MOCK_EXIT', 'MOCK_LOG')
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$sample = 'synthetic-only-' + "quote' and space"
$calls = [System.Collections.Generic.List[string]]::new()

function Assert-DemoCall([object[]] $Arguments, [switch] $Sql) {
    if ($env:SQLCMDPASSWORD -cne $sample) { throw 'Authentication value was altered.' }
    if (($Arguments -join ' ').Contains($sample)) { throw 'Credential exposed in arguments.' }
    if ($Sql -and $Arguments -notcontains '-b') { throw 'SQL errors would not fail the launcher.' }
    if ($Arguments | Where-Object { "$_" -cmatch '^-P' }) { throw 'Password argument retained.' }
    $calls.Add('called')
    $global:LASTEXITCODE = [int]$env:MOCK_EXIT
}

function docker { Assert-DemoCall $args }
function sqlcmd { Assert-DemoCall $args -Sql }
function kubectl {
    Assert-DemoCall $args
    if ($args[0] -eq 'create') {
        $secret = ($input -join "`n") | ConvertFrom-Json
        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.SA_PASSWORD))
        if ($decoded -cne $sample) { throw 'Kubernetes secret input was altered.' }
    }
    else { '192.0.2.1' }
}

New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    $env:MOCK_EXIT = '0'
    $psFiles = @(
        'examples\sqlbyexample\sqlcontainers\step1_runsqlcontainer.ps1'
        'examples\sqlbyexample\sqlcontainers\step3_restoredb.ps1'
        'examples\sqlbyexample\sqlcontainers\step4_querysql.ps1'
        'examples\sqlserver2022\containers\deploy\step1_runsqlcontainer.ps1'
        'examples\sqlserver2022\containers\deploy\step3_restoredb.ps1'
        'examples\sqlserver2022\sqlk8s\ha\step13_createdb.ps1'
        'examples\sqlserver2022\sqlk8s\deploy\step5_create_secret.ps1'
    )
    foreach ($relative in $psFiles) {
        Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue
        $before = $calls.Count
        $blocked = $false
        try { & (Join-Path $root $relative) | Out-Null }
        catch {
            if ($_.Exception.Message -notlike 'Set SQLCMDPASSWORD*') { throw }
            $blocked = $true
        }
        if (-not $blocked -or $before -ne $calls.Count) { throw "Missing input did not fail before side effects: $relative" }
        $env:SQLCMDPASSWORD = $sample
        & (Join-Path $root $relative) | Out-Null
        if ($calls.Count -eq $before) { throw "Mock was not called: $relative" }
        Write-Output "PASS: missing input and private runtime input: $relative"
    }

    $env:MOCK_EXIT = '23'
    $failed = $false
    $before = $calls.Count
    try { & (Join-Path $root $psFiles[2]) | Out-Null }
    catch {
        if ($_.Exception.Message -notlike 'Demo SQL command failed*') { throw }
        $failed = $true
    }
    if (-not $failed -or $calls.Count -ne $before + 1) { throw 'SQL failure did not stop subsequent commands.' }
    $env:MOCK_EXIT = '0'
    Write-Output 'PASS: PowerShell SQL errors propagate'

    $gitExec = git --exec-path
    if ($LASTEXITCODE) { throw 'Git is required.' }
    $gitRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gitExec))
    $shell = Join-Path $gitRoot 'bin\sh.exe'
    $mock = @'
#!/bin/sh
set -eu
case "$0" in
  */sudo)
    case "$1" in --preserve-env=*) shift ;; esac
    exec "$@"
    ;;
  */sleep|*/mkdir) exit 0 ;;
  */sqlcmd)
    case "$*" in
      *-Usqllinux*) test "${SQLCMDPASSWORD:?}" = "$SQLLINUXPASSWORD" ;;
      *) test "${SQLCMDPASSWORD:?}" = "$EXPECTED_DEMO_INPUT" ;;
    esac
    case " $* " in *" -b "*) ;; *) exit 31 ;; esac
    if test -n "${SqlLoginPassword:-}"; then
      raw="${SQLLINUXPASSWORD:-$EXPECTED_DEMO_INPUT}"
      expected_sql=$(printf '%s' "$raw" | sed "s/'/''/g")
      test "$SqlLoginPassword" = "$expected_sql"
    fi
    ;;
  */docker) test "${MSSQL_SA_PASSWORD:?}" = "$EXPECTED_DEMO_INPUT" ;;
esac
case "$*" in *"$EXPECTED_DEMO_INPUT"*) exit 32 ;; esac
printf 'called\n' >> "$MOCK_LOG"
case "$0" in */kubectl) printf '192.0.2.1\n' ;; esac
exit "${MOCK_EXIT:-0}"
'@
    foreach ($name in @('sqlcmd', 'docker', 'kubectl', 'sleep', 'mkdir', 'sudo')) {
        [IO.File]::WriteAllText((Join-Path $fixture $name), $mock.Replace("`r`n", "`n"))
    }
    $env:EXPECTED_DEMO_INPUT = $sample
    $env:MOCK_LOG = (Join-Path $fixture 'calls.log').Replace('\', '/')
    $shellFiles = @(
        'examples\sqlbyexample\sqlk8s\step5_create_secret.sh'
        'examples\sqlbyexample\sqlk8s\step13_createdb.sh'
        'examples\sqlserver2022\containers\replication\db1\db-init.sh'
        'examples\sqlserver2022\containers\replication\db2\db-init.sh'
        'books\sql2019book\ch7_inside_sql_containers\sqlrepl\db1\db-init.sh'
        'books\sqllinuxbook\ch11\dockerrunlatest.sh'
    )
    $driver = @'
set -eu
fixture=$(cygpath -u "$1")
export PATH="$fixture:/usr/bin:/bin"
chmod +x "$fixture"/sqlcmd "$fixture"/docker "$fixture"/kubectl "$fixture"/sleep "$fixture"/mkdir "$fixture"/sudo
exec sh "$fixture/subject.sh"
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'driver.sh'), $driver.Replace("`r`n", "`n"))
    foreach ($relative in $shellFiles) {
        $text = [IO.File]::ReadAllText((Join-Path $root $relative))
        $text = $text.Replace('/opt/mssql-tools/bin/sqlcmd', 'sqlcmd')
        [IO.File]::WriteAllText((Join-Path $fixture 'subject.sh'), $text.Replace("`r`n", "`n"))
        Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:\MSSQL_SA_PASSWORD -ErrorAction SilentlyContinue
        & $shell (Join-Path $fixture 'driver.sh') $fixture *> $null
        if ($LASTEXITCODE -eq 0) { throw "Missing shell input accepted: $relative" }
        $env:SQLCMDPASSWORD = $sample
        $env:MSSQL_SA_PASSWORD = $sample
        & $shell (Join-Path $fixture 'driver.sh') $fixture
        if ($LASTEXITCODE) { throw "Mocked runtime input failed: $relative (exit $LASTEXITCODE)" }
        Write-Output "PASS: shell missing input and private runtime input: $relative"
    }
    if (-not (Test-Path -LiteralPath $env:MOCK_LOG)) { throw 'Shell mocks did not execute.' }
    $env:MOCK_EXIT = '23'
    & $shell (Join-Path $fixture 'driver.sh') $fixture *> $null
    if ($LASTEXITCODE -ne 23) { throw 'Shell failure did not propagate.' }
    Write-Output 'PASS: shell command errors propagate'

    $env:MOCK_EXIT = '0'
    $env:SQLCMDPASSWORD = $sample
    $env:SQLLINUXPASSWORD = 'synthetic-user-' + "different' value"
    Remove-Item Env:\SqlLoginPassword -ErrorAction SilentlyContinue
    $wwi = [IO.File]::ReadAllText((Join-Path $root 'books\sqllinuxbook\ch3\createwwi.sh'))
    [IO.File]::WriteAllText((Join-Path $fixture 'subject.sh'), $wwi.Replace("`r`n", "`n"))
    $wwiDriver = $driver.Replace('exec sh "$fixture/subject.sh"', 'exec sh "$fixture/subject.sh" example.invalid')
    [IO.File]::WriteAllText((Join-Path $fixture 'driver.sh'), $wwiDriver.Replace("`r`n", "`n"))
    & $shell (Join-Path $fixture 'driver.sh') $fixture
    if ($LASTEXITCODE) { throw 'Distinct administrator/user credential flow failed.' }
    Write-Output 'PASS: distinct administrator/user passwords and SQL escaping'

    Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue
    foreach ($relative in @(
        'examples\sqllinux\demo_sql_docker\dockerrun.cmd'
        'examples\sqllinux\demo_sql_docker\docker_restorewwi.cmd'
        'books\sqllinuxbook\ch3\createwwi.cmd'
    )) {
        & $env:ComSpec /d /c ('call "' + (Join-Path $root $relative) + '"') *> $null
        if ($LASTEXITCODE -ne 1) { throw "Windows launcher accepted missing input: $relative" }
        Write-Output "PASS: Windows launcher rejects missing input: $relative"
    }
}
finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
