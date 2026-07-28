<#
.SYNOPSIS
    End-to-end: provision the APIM AI gateway, deploy the gateway-aware clinical
    assistance proc (09-ai-gateway.sql), and verify a live call succeeds — in one
    command. No manual copy-paste of the AUDIENCE.

.DESCRIPTION
    Automates the gateway rollout end-to-end:
      1. Runs setup-ai-gateway.ps1 (APIM StandardV2 + validate-azure-ad-token policy
         accepting ONLY the wardgeneral server MI, on the first-party Cognitive
         Services audience — no app registration). If the instance already exists,
         setup skips the ~30-45 min provision and just re-applies the policy.
      2. Deploys sql\09-ai-gateway.sql as-is (the credential already uses the
         first-party audience — nothing to inject or paste).
      3. Runs  EXEC clinical.GenerateClinicalAssistance @EncounterId = <id>
         through the gateway and confirms a real (200) result — not the proc's
         "AI assistance unavailable" fallback. Retries transient 401/403 while
         the role assignment / token validation settle.

    Fully passwordless throughout (Entra tokens, managed identity). No key.

    Idempotent: setup-ai-gateway.ps1 and 09-ai-gateway.sql are both safe to
    re-run, so re-running this after a partial failure just resumes.

.PARAMETER ContentSafety
    Also run add-content-safety.ps1 between provisioning and the SQL deploy.

.PARAMETER SkipSetup
    Skip step 1 (assume the gateway already exists) and go straight to deploy+test.
    Useful to re-verify without waiting on APIM.

.PARAMETER Force
    Passed through to setup-ai-gateway.ps1 (delete + recreate the APIM instance).

.EXAMPLE
    .\run-ai-gateway-e2e.ps1
    .\run-ai-gateway-e2e.ps1 -ContentSafety
    .\run-ai-gateway-e2e.ps1 -SkipSetup        # gateway already up — just deploy + test
#>
[CmdletBinding()]
param(
    [string] $Server          = 'collierhealth-17.database.windows.net',
    [string] $Database        = 'wardgeneral',
    [string] $SqlServerName   = 'collierhealth-17',
    [int]    $EncounterId     = 1001,
    [string] $SqlSim          = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe',
    [switch] $ContentSafety,
    [switch] $SkipSetup,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# 09-ai-gateway.sql lives in ../sql in the presentation kit, or co-located in a flat (book) folder.
$sqlFile = Join-Path $here '..\sql\09-ai-gateway.sql'
if (-not (Test-Path $sqlFile)) { $sqlFile = Join-Path $here '09-ai-gateway.sql' }
if (-not (Test-Path $SqlSim))  { throw "sqlsim not found at $SqlSim (build it or pass -SqlSim)." }
if (-not (Test-Path $sqlFile)) { throw "09-ai-gateway.sql not found at $sqlFile" }

function Get-DbToken {
    # Acquire an Entra token for Azure SQL, waiting through transient CLI/network
    # blips instead of returning an empty token (never hand sqlsim an empty -T).
    param([int]$MaxWaitMinutes = 15)
    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    $delay = 5
    while ($true) {
        $t = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null)
        if ($t) { $t = $t.Trim() }
        if ($t -and $t.Length -gt 100 -and $t -notmatch '\s') { return $t }
        if ((Get-Date) -ge $deadline) { return $null }
        Write-Host "  Entra token unavailable - retrying in ${delay}s..." -ForegroundColor Gray
        Start-Sleep -Seconds $delay
        if ($delay -lt 30) { $delay = [math]::Min(30, $delay * 2) }
    }
}

function Invoke-Sql {
    param([string]$Sql)
    $token = Get-DbToken
    if (-not $token) { throw 'Could not acquire an Entra token for Azure SQL (az login?).' }
    $f = Join-Path $env:TEMP ("wg-gw-{0}.sql" -f ([guid]::NewGuid().ToString('N')))
    # sqlsim/T-SQL want a BOM-free UTF-8 file.
    [System.IO.File]::WriteAllText($f, $Sql, [System.Text.UTF8Encoding]::new($false))
    try {
        return (& $SqlSim -S $Server -d $Database -T $token -N s -i $f 2>&1 | Out-String)
    } finally {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' AI Gateway — end-to-end (provision + deploy + verify)' -ForegroundColor Cyan
Write-Host "  Server   : $Server / $Database"    -ForegroundColor Gray
Write-Host '  Audience : https://cognitiveservices.azure.com (first-party, no app reg)' -ForegroundColor Gray
Write-Host "  Test     : EncounterId $EncounterId" -ForegroundColor Gray
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ''

# ── 1. Provision the gateway (blocks until APIM provisioning Succeeds) ──
if ($SkipSetup) {
    Write-Host '[1/3] Skipping provisioning (-SkipSetup).' -ForegroundColor Yellow
} else {
    Write-Host '[1/3] Provisioning APIM gateway (setup-ai-gateway.ps1, ~30-45 min)...' -ForegroundColor Yellow
    $setup = Join-Path $here 'setup-ai-gateway.ps1'
    $setupArgs = @{ SqlServerName = $SqlServerName }
    if ($Force) { $setupArgs['Force'] = $true }
    & $setup @setupArgs
    if ($LASTEXITCODE -ne 0) { throw "setup-ai-gateway.ps1 failed (exit $LASTEXITCODE)." }

    if ($ContentSafety) {
        Write-Host ''
        Write-Host '[1b] Adding content safety (add-content-safety.ps1)...' -ForegroundColor Yellow
        & (Join-Path $here 'add-content-safety.ps1')
        if ($LASTEXITCODE -ne 0) { throw "add-content-safety.ps1 failed (exit $LASTEXITCODE)." }
    }
}
Write-Host ''

# ── 2. Deploy 09-ai-gateway.sql (first-party audience already baked in) ──
Write-Host '[2/3] Deploying gateway-aware proc (09-ai-gateway.sql)...' -ForegroundColor Yellow
$dtoken = Get-DbToken
if (-not $dtoken) { throw 'Could not acquire an Entra token for Azure SQL (az login?).' }
$deployOut = & $SqlSim -S $Server -d $Database -T $dtoken -N s -stoponerror -i $sqlFile 2>&1 | Out-String
$deployCode = $LASTEXITCODE
Write-Host $deployOut
if ($deployCode -ne 0) { throw "09-ai-gateway.sql deploy failed (sqlsim exit $deployCode)." }
Write-Host '  Deployed.' -ForegroundColor Green
Write-Host ''

# ── 3. Verify a live gateway call — retry while RBAC / token audience propagate ──
Write-Host '[3/3] Verifying a live gateway call...' -ForegroundColor Yellow
$testSql = @"
SET NOCOUNT ON;
DECLARE @r TABLE (EncounterId INT, PatientName NVARCHAR(200), SuggestedTriageFlag NVARCHAR(20),
                  Summary NVARCHAR(MAX), GroundedOnNoteIds NVARCHAR(200), Path NVARCHAR(20), ProcessingTimeMs INT);
INSERT INTO @r EXEC clinical.GenerateClinicalAssistance @EncounterId = $EncounterId, @UseGateway = 1;
DECLARE @summary NVARCHAR(MAX) = (SELECT TOP 1 Summary FROM @r);
DECLARE @path    NVARCHAR(20)  = (SELECT TOP 1 Path FROM @r);
DECLARE @flag    NVARCHAR(20)  = (SELECT TOP 1 SuggestedTriageFlag FROM @r);
IF @summary LIKE 'AI assistance unavailable%'
    PRINT 'GATEWAY_FAIL ' + LEFT(@summary, 400);
ELSE
    PRINT 'GATEWAY_PASS path=' + ISNULL(@path,'?') + ' flag=' + ISNULL(@flag,'?') + ' summary=' + LEFT(ISNULL(@summary,''), 200);
"@

$maxTries = 16          # ~8 min of 30s retries while role assignment / audience propagate
$try = 0
$passed = $false
while ($true) {
    $try++
    $out = Invoke-Sql -Sql $testSql
    if ($out -match 'GATEWAY_PASS') {
        Write-Host ''
        Write-Host ($out -split "`n" | Where-Object { $_ -match 'GATEWAY_PASS' } | Select-Object -First 1) -ForegroundColor Green
        $passed = $true
        break
    }
    $failLine = ($out -split "`n" | Where-Object { $_ -match 'GATEWAY_FAIL' } | Select-Object -First 1)
    # 401/403 right after provisioning = role/audience not propagated yet → retry.
    if ($try -lt $maxTries -and ($out -match '401|403|Unauthorized|IPValidation|AuthenticationFailed|not authorized')) {
        Write-Host "  attempt $try/$maxTries — auth not propagated yet (retry 30s): $failLine" -ForegroundColor Gray
        Start-Sleep -Seconds 30
        continue
    }
    Write-Host ''
    Write-Host "  $failLine" -ForegroundColor Red
    if ($out -notmatch 'GATEWAY_FAIL') { Write-Host $out -ForegroundColor Red }
    break
}

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
if ($passed) {
    Write-Host ' RESULT: PASS — gateway call returned a live gpt-5 result (200).' -ForegroundColor Green
    Write-Host "  DB --MI token--> APIM (validate-azure-ad-token) --MI--> gpt-5" -ForegroundColor Gray
    Write-Host '  Audience: https://cognitiveservices.azure.com (first-party — no app registration).' -ForegroundColor Gray
    exit 0
} else {
    Write-Host ' RESULT: FAIL — see the error above.' -ForegroundColor Red
    Write-Host '  Common causes: SQL server has no system-assigned MI (setup preflight catches this);' -ForegroundColor Gray
    Write-Host '  role assignment / token-audience propagation still settling (re-run with -SkipSetup);' -ForegroundColor Gray
    Write-Host '  or the audience SP could not be updated to clear "assignment required" (setup warns).' -ForegroundColor Gray
    exit 1
}
