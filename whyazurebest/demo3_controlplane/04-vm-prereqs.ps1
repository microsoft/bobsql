<#
.SYNOPSIS
    Step 5 of 6. Installs the client prerequisites inside the VM.

.DESCRIPTION
    Runs from the presenter's laptop, but every command executes INSIDE the VM
    via 'az vm run-command'. That goes through ARM, not the VNet, so it keeps
    working later when public network access is disabled.

    Installs ODBC Driver 18 for SQL Server (sqlsim's only hard dependency) and
    the VC++ 2015-2022 x64 redistributable, and creates C:\demo.

.NOTES
    The MSI property IACCEPTMSODBCSQLLICENSETERMS must be uppercase or the
    install silently does nothing.
#>

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step "Creating $VmKitDir on the VM"
Invoke-VmScript "New-Item -ItemType Directory -Force -Path '$VmKitDir' | Out-Null; 'ok'" | Out-Null
Write-Ok 'Created'

# Must come first. The ODBC 18 MSI hard-fails with "Error 1723 ... please
# install the Visual C++ Redistributable" if this is not already present.
Write-Step 'Checking for the VC++ 2015-2022 x64 redistributable'
$vc = Invoke-VmScript @"
`$k = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
if ((Test-Path `$k) -and (Get-ItemProperty `$k).Installed -eq 1) { 'PRESENT' } else { 'MISSING' }
"@
if ($vc -match 'PRESENT') {
    Write-Skip 'Already installed'
}
else {
    Write-Ok 'Missing. Installing.'
    $result = Invoke-VmScript @"
`$ErrorActionPreference = 'Stop'
`$exe = Join-Path `$env:TEMP 'vc_redist.x64.exe'
Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile `$exe -UseBasicParsing
Start-Process `$exe -ArgumentList '/install','/quiet','/norestart' -Wait
`$k = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
if ((Test-Path `$k) -and (Get-ItemProperty `$k).Installed -eq 1) { 'PRESENT' } else { 'MISSING' }
"@
    if ($result -notmatch 'PRESENT') {
        throw "The VC++ redistributable did not install.`n$result"
    }
    Write-Ok 'Installed'
}

Write-Step 'Checking for ODBC Driver 18'
$odbc = Invoke-VmScript @"
if (Get-OdbcDriver -Name 'ODBC Driver 18 for SQL Server' -ErrorAction SilentlyContinue) { 'PRESENT' } else { 'MISSING' }
"@
if ($odbc -match 'PRESENT') {
    Write-Skip 'Already installed'
}
else {
    Write-Ok 'Missing. Installing (this takes a minute).'
    $result = Invoke-VmScript @"
`$ErrorActionPreference = 'Stop'
`$msi = Join-Path `$env:TEMP 'msodbcsql18.msi'
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2358430' -OutFile `$msi -UseBasicParsing
`$p = Start-Process msiexec.exe -ArgumentList "/quiet","/passive","/qn","/i","`$msi","IACCEPTMSODBCSQLLICENSETERMS=YES","ADDLOCAL=ALL" -Wait -PassThru
"exit=`$(`$p.ExitCode)"
if (Get-OdbcDriver -Name 'ODBC Driver 18 for SQL Server' -ErrorAction SilentlyContinue) { 'PRESENT' } else { 'MISSING' }
"@
    if ($result -notmatch 'PRESENT') {
        throw "ODBC Driver 18 did not install.`n$result"
    }
    Write-Ok 'Installed'
}

Write-Step "Checking for the demo kit at $VmKitDir"
$kit = Invoke-VmScript "if (Test-Path '$VmSqlSim') { 'PRESENT' } else { 'MISSING' }"
if ($kit -match 'PRESENT') {
    Write-Ok 'sqlsim.exe is already on the VM'
}
else {
    Write-Warn 'sqlsim.exe is NOT on the VM yet. That is your job - see the handoff below.'
}

Write-Host ''
Write-Ok 'Step 5 complete. Copy the demo kit to the VM, then: .\05-verify.ps1'
