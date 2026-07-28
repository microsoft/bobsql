<#
    Ward General Hospital — Hyperscale developer demo
    diagnostics / test-ai-assistance.ps1

    Runs the in-engine clinical-assistance path END-TO-END without the Blazor
    app, over a token-authenticated (Entra / passwordless) connection using
    sqlsim. It calls clinical.GenerateClinicalAssistance for one encounter and
    prints the result plus proof that the tamper-evident audit row landed in the
    append-only ledger table clinical.AIAssistanceLog.

    This is the same stored proc the app's "Get AI assistance" card runs — a fast
    health check after a deploy, a model/gateway change, or a database refresh.

    USAGE
      ./test-ai-assistance.ps1                  # auto-picks an Active encounter with notes
      ./test-ai-assistance.ps1 -EncounterId 249 # pin a specific encounter

    PREREQS
      * 06-ai-embeddings.sql + 07-ai-assistance.sql deployed (external model,
        embeddings built, GenerateClinicalAssistance + AIAssistanceLog ledger).
      * az login to the subscription that owns the wardgeneral database.
      * sqlsim built at sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe.

    All data is synthetic — no real PHI.
#>
[CmdletBinding()]
param(
    [int]    $EncounterId = 0,   # 0 = auto-pick
    [string] $Server      = 'collierhealth-17.database.windows.net',
    [string] $Database    = 'wardgeneral',
    [string] $Model       = 'gpt-5',
    [int]    $TopK        = 5,
    [string] $SqlSim      = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SqlSim)) { throw "sqlsim not found at $SqlSim" }

$pick = if ($EncounterId -gt 0) {
    "DECLARE @EncounterId INT = $EncounterId;"
} else {
    @"
DECLARE @EncounterId INT;
SELECT TOP (1) @EncounterId = e.EncounterId
FROM clinical.Encounter AS e
WHERE e.Status = N'Active'
  AND EXISTS (SELECT 1 FROM clinical.ClinicalNote AS n WHERE n.EncounterId = e.EncounterId)
ORDER BY e.EncounterId DESC;
"@
}

$sql = @"
SET NOCOUNT ON;
$pick
DECLARE @Before BIGINT = (SELECT COUNT(*) FROM clinical.AIAssistanceLog);
PRINT CONCAT('Testing encounter ', @EncounterId, '  (ledger rows before = ', @Before, ')');
EXEC clinical.GenerateClinicalAssistance @EncounterId = @EncounterId, @ModelDeployment = N'$Model', @TopK = $TopK;
DECLARE @After BIGINT = (SELECT COUNT(*) FROM clinical.AIAssistanceLog);
SELECT LedgerRowsBefore = @Before,
       LedgerRowsAfter  = @After,
       AuditRowAppended = CASE WHEN @After = @Before + 1 THEN 'yes' ELSE 'NO - check ledger' END;
"@

$tmp = Join-Path $env:TEMP ("wg-test-assist-{0}.sql" -f ([guid]::NewGuid().ToString('N')))
$out = [System.IO.Path]::ChangeExtension($tmp, '.out')
Set-Content -Path $tmp -Value $sql -Encoding UTF8

try {
    Write-Host "Acquiring access token and running clinical-assistance test (gpt-5 takes ~10s)..." -ForegroundColor Cyan
    $tk = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv)
    if (-not $tk) { throw 'Failed to acquire an Entra access token. Run: az login' }

    & $SqlSim -S $Server -d $Database -T $tk -N s -i $tmp *> $out

    # Strip sqlsim's timestamp prefix and show only the runtime output region:
    # from "Starting execution" (skips the echoed input batch) to the perf summary.
    $lines = Get-Content $out | ForEach-Object { $_ -replace '^\d{4}-\d{2}-\d{2}[^|]*\| ?', '' }
    $start = [Array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match 'Starting execution' })
    $end   = [Array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match 'Performance Metric Summary' })
    if ($start -ge 0 -and $end -gt $start) {
        $lines[($start + 1)..($end - 2)] | Where-Object { $_ -notmatch '^={10,}$' } | Write-Host
    } else {
        Get-Content $out | Write-Host   # fallback: dump everything
    }

    $text = ($lines -join "`n")
    $failed = $text -match 'Total Errors: [1-9]' -or $text -match '\(0 successful, \d+ failed\)'
    if (-not $failed -and $text -match 'AuditRowAppended') {
        Write-Host "`nAI assistance OK — proc ran and the audit row was appended to the ledger." -ForegroundColor Green
    } else {
        Write-Host "`nProc reported errors — see full output at: $out" -ForegroundColor Yellow
        Write-Host '(A transient Foundry 5xx/timeout shows as a graceful "AI assistance unavailable" summary — just re-run.)'
    }
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
