<#
    Ward General Hospital — Hyperscale developer demo
    generate-embeddings.ps1 : token-refreshing, RESUMABLE driver that embeds the
                              full clinical-note corpus in chunks.

    WHY A DRIVER (not one big INSERT):
      A single set-based INSERT over ~60k notes runs ~3.5 hr, but an Entra access
      token expires in ~1 hr and Azure SQL drops the token-authenticated
      connection at expiry — so the one-shot run dies mid-way. This driver embeds
      in CHUNKS, acquiring a FRESH token per chunk (each chunk is minutes, well
      inside the token lifetime). It is RESUMABLE: each chunk only touches notes
      that don't yet have an embedding (WHERE NOT EXISTS), so if a chunk fails or
      the machine sleeps, just re-run — it continues where it left off. NULL
      embeddings (throttle) are skipped and retried next pass, guaranteeing
      forward progress. Safe to run in the BACKGROUND while you do other work.

    PREREQS:
      * 06-ai-embeddings.sql already run (external model + credential + table).
      * The embedding deployment (text-embedding-3-large) has enough TPM. The
        deploy-wardgeneral-ai skill already creates it at --sku-capacity 100, so
        a from-scratch deploy needs no change. Only if you inherited a low cap
        (e.g. 3) does this crawl; raise it with:
          az cognitiveservices account deployment ... --sku-capacity 100
      * sqlsim built at sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe.

    All data is synthetic — no real PHI.
#>
[CmdletBinding()]
param(
    [string] $Server    = 'collierhealth-17.database.windows.net',
    [string] $Database  = 'wardgeneral',
    [int]    $BatchSize = 2000,
    [string] $SqlSim    = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe',
    [string] $LogPath   = (Join-Path $PSScriptRoot 'embeddings-progress.log')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SqlSim)) { throw "sqlsim not found at $SqlSim" }

function Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

$chunkSql = @"
SET NOCOUNT ON;
DECLARE @b INT = $BatchSize;
INSERT INTO clinical.ClinicalNoteEmbeddings (NoteId, Embedding)
SELECT NoteId, emb
FROM (
    SELECT TOP (@b)
        n.NoteId,
        AI_GENERATE_EMBEDDINGS(n.NoteText USE MODEL WardGeneralEmbeddingModel) AS emb
    FROM clinical.ClinicalNote AS n
    WHERE NOT EXISTS (SELECT 1 FROM clinical.ClinicalNoteEmbeddings e WHERE e.NoteId = n.NoteId)
) AS x
WHERE x.emb IS NOT NULL;      -- skip throttled (NULL) rows; retried next pass
DECLARE @done INT = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings);
DECLARE @total INT = (SELECT COUNT(*) FROM clinical.ClinicalNote);
PRINT CONCAT('PROGRESS ', @done, ' / ', @total);
"@
$chunkFile = Join-Path $env:TEMP 'wg-embed-chunk.sql'
Set-Content -Path $chunkFile -Value $chunkSql -Encoding UTF8

function Get-DbToken {
    # Acquire an Entra access token, WAITING through transient network loss instead of
    # returning an empty token. Returns a valid token, or $null only after being offline
    # for $MaxWaitMinutes. This is the key hardening: never hand sqlsim an empty -T.
    param([int]$MaxWaitMinutes = 120)
    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    $delay = 10
    while ($true) {
        $t = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null)
        if ($t) { $t = $t.Trim() }
        if ($t -and $t.Length -gt 100 -and $t -notmatch '\s') { return $t }
        if ((Get-Date) -ge $deadline) { return $null }
        Log "  Entra token unavailable (offline?) - retrying in ${delay}s (not a stall)..."
        Start-Sleep -Seconds $delay
        if ($delay -lt 60) { $delay = [math]::Min(60, $delay * 2) }
    }
}

function Test-Transient([string]$text) {
    # True for network / connection / empty-token errors that should be retried WITHOUT
    # counting toward the no-progress abort.
    return ($text -match 'Access token cannot be empty' -or
            $text -match 'Login timeout expired' -or
            $text -match 'TCP Provider' -or
            $text -match 'Named Pipes Provider' -or
            $text -match 'Communication link failure' -or
            $text -match 'transport-level error' -or
            $text -match 'network-related or instance-specific' -or
            $text -match 'Cannot open server' -or
            $text -match 'Client unable to establish connection' -or
            $text -match 'getaddrinfo failed')
}

Log "=== Embedding run started (batch=$BatchSize) ==="
$stall = 0        # genuine no-forward-progress passes (throttle / endpoint down)
$transient = 0    # consecutive network / token errors (NOT counted as stalls)
$last  = -1
while ($true) {
    $token = Get-DbToken -MaxWaitMinutes 120
    if (-not $token) { Log "ABORT: no Entra token after 120 min offline."; break }

    $out = & $SqlSim -S $Server -d $Database -T $token -N s -i $chunkFile 2>&1 | Out-String

    # Transient network / token errors: wait and retry, do NOT count as a stall.
    if (Test-Transient $out) {
        $transient++
        Log "  transient network/SQL error (#$transient) - waiting 30s (not a stall). Tail:"
        Log ($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3 | Out-String)
        if ($transient -ge 40) { Log "ABORT: 40 consecutive transient errors (~20 min) - server/endpoint unreachable."; break }
        Start-Sleep -Seconds 30
        continue
    }
    $transient = 0

    $m = [regex]::Match($out, 'PROGRESS (\d+) / (\d+)')
    if (-not $m.Success) {
        Log "WARN: no PROGRESS line this pass. Output tail:"
        Log ($out -split "`n" | Select-Object -Last 6 | Out-String)
        $stall++
        if ($stall -ge 10) { Log "ABORT: 10 passes with no parseable progress."; break }
        Start-Sleep -Seconds 30
        continue
    }
    $done  = [int]$m.Groups[1].Value
    $total = [int]$m.Groups[2].Value
    $pct   = if ($total) { [math]::Round(100.0 * $done / $total, 1) } else { 0 }
    Log ("  {0} / {1} embedded ({2}%)" -f $done, $total, $pct)

    if ($done -ge $total) { Log "=== All notes embedded ==="; break }
    if ($done -le $last)  { $stall++ } else { $stall = 0 }
    if ($stall -ge 10)    { Log "ABORT: no forward progress in 10 passes (deployment throttled/down?)."; break }
    $last = $done
}

# Build the DiskANN index once the corpus is embedded (>= 100 rows).
if ($last -ge 100 -or $done -ge 100) {
    Log "=== Building DiskANN vector index (if not present) ==="
    $idxSql = @"
SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; SET ARITHABORT ON;
IF (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings) >= 100
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
    CREATE VECTOR INDEX VIX_ClinicalNoteEmbeddings_Embedding
    ON clinical.ClinicalNoteEmbeddings (Embedding)
    WITH (METRIC = 'cosine', TYPE = 'diskann');
PRINT 'Index step complete.';
"@
    $idxFile = Join-Path $env:TEMP 'wg-embed-index.sql'
    Set-Content -Path $idxFile -Value $idxSql -Encoding UTF8
    $token = Get-DbToken
    if ($token) { & $SqlSim -S $Server -d $Database -T $token -N s -i $idxFile 2>&1 | Out-String | Write-Host }
    else { Log "WARN: no token for index build - re-run later to create the DiskANN index." }
    Remove-Item $idxFile -ErrorAction SilentlyContinue
}
Remove-Item $chunkFile -ErrorAction SilentlyContinue
Log "=== Embedding run finished ==="
