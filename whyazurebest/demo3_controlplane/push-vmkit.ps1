<#
.SYNOPSIS
    Copies the three vmkit scripts into C:\demo on the VM.

.DESCRIPTION
    Runs from the laptop. Uses az vm run-command, so it needs no RDP session,
    no file share, and no inbound network path to the VM.

    Only sqlsim.exe still has to go over RDP - it is too large to push through
    run-command reliably.

    Content is base64-encoded on the way in so quoting, backticks and
    non-ASCII characters survive the trip intact.
#>

. "$PSScriptRoot\00-config.ps1"

Write-Beat 'Pushing the vmkit scripts to the VM'

$files = @('config.ps1', 'query.ps1', 'dns.ps1')

foreach ($file in $files) {
    $local = Join-Path $PSScriptRoot "vmkit\$file"
    if (-not (Test-Path $local)) { throw "Missing $local" }

    Write-Step "Writing $VmKitDir\$file (runs inside the VM)"

    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($local))

    $result = Invoke-VmScript @"
`$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path '$VmKitDir' -Force | Out-Null
`$bytes = [Convert]::FromBase64String('$b64')
[System.IO.File]::WriteAllBytes('$VmKitDir\$file', `$bytes)
"OK `$((Get-Item '$VmKitDir\$file').Length) bytes"
"@

    if ($result -notmatch 'OK\s+\d+\s+bytes') {
        throw "Failed to write $file.`n$result"
    }
    Write-Ok ($result.Trim() -split "`n" | Where-Object { $_ -match 'OK' } | Select-Object -First 1)
}

Write-Step "Listing $VmKitDir"
Write-Host (Invoke-VmScript "Get-ChildItem '$VmKitDir' | Select-Object Name, Length | Format-Table -AutoSize | Out-String")

if ((Invoke-VmScript "if (Test-Path '$VmSqlSim') { 'PRESENT' } else { 'MISSING' }") -match 'PRESENT') {
    Write-Ok 'sqlsim.exe is already on the VM. The kit is complete.'
}
else {
    Write-Warn "sqlsim.exe is still missing. Copy it over RDP:"
    Write-Host "    from  $SqlSimLocal"
    Write-Host "    to    $VmKitDir"
}
