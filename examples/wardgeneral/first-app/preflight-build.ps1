#requires -Version 7.0
<#
    Ward General Hospital Digital Chart Application
    preflight-build.ps1 : check that this machine can BUILD the app.

    Local toolchain only. Nothing here touches Azure, because compiling the
    solution does not need a cloud sign-in, a firewall rule, or a database.
    Those belong to preflight-run.ps1.

    Checks:
      1. .NET SDK        major version 10 or later    (failure)
      2. HTTPS dev cert  present and trusted          (warning)

    build.ps1 calls this automatically. Run it on its own the first time you
    sit down with the code.

    Exit code 0 = ready to build. 1 = at least one failure.

    Usage:
      ./preflight-build.ps1
#>
[CmdletBinding()]
param()

$failures = 0
$warnings = 0

function Write-Check {
    param([ValidateSet('pass', 'warn', 'fail')][string]$Result, [string]$Name, [string]$Detail)
    $mark, $color = switch ($Result) {
        'pass' { '  OK  ', 'Green' }
        'warn' { ' WARN ', 'Yellow' }
        'fail' { ' FAIL ', 'Red' }
    }
    Write-Host "[$mark] " -ForegroundColor $color -NoNewline
    Write-Host $Name -NoNewline
    if ($Detail) { Write-Host " - $Detail" -ForegroundColor DarkGray } else { Write-Host '' }
}

Write-Host "`nWard General - build pre-flight`n" -ForegroundColor Cyan

# -- 1. .NET SDK ------------------------------------------------------------
# The app targets net10.0. An older SDK fails with NETSDK1045, which reads as a
# project problem rather than a missing install, so name it plainly here.
$minSdkMajor = 10
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Check fail '.NET SDK' 'not found on PATH - install .NET 10 from https://dotnet.microsoft.com/download'
    $failures++
}
else {
    $sdkMajors = @(dotnet --list-sdks 2>$null) |
        ForEach-Object { if ($_ -match '^(\d+)\.') { [int]$Matches[1] } }
    $best = ($sdkMajors | Measure-Object -Maximum).Maximum
    if (-not $best) {
        Write-Check fail '.NET SDK' 'dotnet is on PATH but no SDK is installed (runtime only?)'
        $failures++
    }
    elseif ($best -lt $minSdkMajor) {
        Write-Check fail '.NET SDK' "found $best.x, need $minSdkMajor.0 or later"
        $failures++
    }
    else {
        Write-Check pass '.NET SDK' "$best.x"
    }

    # -- 2. HTTPS developer certificate ------------------------------------
    # Warning, not a failure: the app still builds and runs, the browser just
    # objects. We do NOT install it -- trusting a root certificate on the
    # reader's machine is the reader's decision, not ours.
    dotnet dev-certs https --check --trust 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Check warn 'HTTPS dev certificate' "missing or untrusted - run 'dotnet dev-certs https --trust'"
        $warnings++
    }
    else {
        Write-Check pass 'HTTPS dev certificate' 'trusted'
    }
    $global:LASTEXITCODE = 0
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host "Build pre-flight failed: $failures problem(s) to fix.`n" -ForegroundColor Red
    exit 1
}
elseif ($warnings -gt 0) {
    Write-Host "Build pre-flight passed with $warnings warning(s).`n" -ForegroundColor Yellow
}
else {
    Write-Host "Build pre-flight passed.`n" -ForegroundColor Green
}
exit 0
