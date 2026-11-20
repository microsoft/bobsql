#requires -Version 7.0
#requires -Modules SqlServer
<#
.SYNOPSIS
Builds and verifies CustomerServiceDesk with real local Ollama embeddings.
.DESCRIPTION
Adds missing schema and synthetic seed rows without deleting data or overwriting
case edits. Resumes missing/stale embeddings for an immutable model profile.
Uses a secure SQL credential prompt unless -SqlCredential or the explicit
local-only -UseContainerCredentials switch is supplied. No secrets are written.
#>
[CmdletBinding()]
param(
    [string]$Server = 'localhost,14332',
    [PSCredential]$SqlCredential,
    [switch]$UseContainerCredentials,
    [ValidateNotNullOrEmpty()]
    [string]$EmbeddingModel = 'nomic-embed-text:v1.5',
    [ValidateNotNullOrEmpty()]
    [string]$ProfileName = 'ollama-nomic-v1.5',
    [ValidateRange(1, 32)]
    [int]$BatchSize = 16
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Import-Module SqlServer -ErrorAction Stop
. (Join-Path $PSScriptRoot 'embedding-helpers.ps1')
& (Join-Path $PSScriptRoot 'preflight.ps1') -EmbeddingModel $EmbeddingModel

if ($UseContainerCredentials) {
    if ($SqlCredential -or $Server -ne 'localhost,14332') {
        throw '-UseContainerCredentials is exclusive to localhost,14332 and cannot be combined with -SqlCredential.'
    }
    $settings = docker inspect --format '{{json .Config.Env}}' sqldbcontainer
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the local container settings.' }
    $password = @($settings | ConvertFrom-Json | Where-Object { $_.StartsWith('MSSQL_SA_PASSWORD=') })
    if ($password.Count -ne 1) { throw 'The local container has no unique initial SQL password setting.' }
    $SqlCredential = [PSCredential]::new('sa',
        [Net.NetworkCredential]::new('', $password[0].Substring('MSSQL_SA_PASSWORD='.Length)).SecurePassword)
    $settings = $null
    $password = $null
}
if (-not $SqlCredential) {
    $SqlCredential = Get-Credential -UserName sa -Message 'SQL setup administrator (not registry credentials)'
    if (-not $SqlCredential) { throw 'A SQL setup credential is required.' }
}
$connectionString = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
$connectionString['Data Source'] = $Server
$connectionString['Initial Catalog'] = 'master'
$connectionString['Encrypt'] = $true
$connectionString['TrustServerCertificate'] = $Server -eq 'localhost,14332'
$connectionString['Application Name'] = 'CustomerServiceDesk.DatabaseSetup'
$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($connectionString.ConnectionString)
$securePassword = $SqlCredential.Password.Copy()
$securePassword.MakeReadOnly()
$connection.Credential = [Microsoft.Data.SqlClient.SqlCredential]::new(
    $SqlCredential.UserName, $securePassword)

function Invoke-SetupQuery {
    param([string]$Query, [hashtable]$Parameters = @{}, [switch]$Rows)
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = $Query
        $command.CommandTimeout = 300
        foreach ($name in $Parameters.Keys) {
            [void]$command.Parameters.AddWithValue("@$name", $Parameters[$name])
        }
        if ($Rows) {
            $reader = $command.ExecuteReader()
            try {
                $table = [Data.DataTable]::new()
                $table.Load($reader)
                return ,$table
            } finally { $reader.Dispose() }
        } else {
            [void]$command.ExecuteNonQuery()
        }
    } finally { $command.Dispose() }
}

function Invoke-SetupScript {
    param([string]$Name)
    Write-Host "Running $Name..."
    $sql = Get-Content -LiteralPath (Join-Path $PSScriptRoot $Name) -Raw
    foreach ($batch in [regex]::Split($sql, '(?im)^\s*GO\s*(?:--[^\r\n]*)?\r?$')) {
        $use = [regex]::Match($batch, '(?i)^\s*USE\s+([A-Za-z0-9_]+)\s*;')
        if ($use.Success) {
            $database = $use.Groups[1].Value
            if ($connection.Database -ne $database) {
                # Azure SQL requires a new connection, not a cross-database USE.
                $connection.Close()
                $connectionString['Initial Catalog'] = $database
                $connection.ConnectionString = $connectionString.ConnectionString
                $connection.Open()
            }
            $batch = $batch.Substring($use.Length)
        }
        if (-not [string]::IsNullOrWhiteSpace($batch)) {
            $result = Invoke-SetupQuery -Query $batch -Rows
            if ($result.Rows.Count -gt 0) { $result | Format-Table -AutoSize | Out-Host }
        }
    }
}

try {
    $connection.Open()
    Invoke-SetupScript '01-create-database.sql'
    Invoke-SetupQuery @'
DECLARE @LockResult int;
EXEC @LockResult = sys.sp_getapplock @Resource = 'CustomerServiceDesk.DatabaseSetup',
    @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 0;
IF @LockResult < 0 THROW 51104, 'Another database setup is already running.', 1;
'@
    Invoke-SetupScript '04-create-schema.sql'
    Invoke-SetupScript '08-app-procedures.sql'
    Invoke-SetupScript '05-seed-data.sql'

    $models = Invoke-RestMethod -Uri http://localhost:11434/api/tags -TimeoutSec 30
    $model = @($models.models | Where-Object { $_.name -eq $EmbeddingModel })
    if ($model.Count -ne 1 -or [string]::IsNullOrWhiteSpace($model[0].digest)) {
        throw 'Cannot identify the exact installed embedding model digest.'
    }
    $profileRow = Invoke-SetupQuery -Rows -Parameters @{
        Name = $ProfileName; Model = $EmbeddingModel; Digest = $model[0].digest
    } -Query @'
IF EXISTS (SELECT 1 FROM dbo.EmbeddingProfiles WHERE ProfileName = @Name
           AND (Provider <> 'Ollama' OR ModelName <> @Model OR ModelVersion <> @Digest
                OR Dimensions <> 768 OR DocumentPrefix <> N'search_document: ' OR QueryPrefix <> N'search_query: '))
    THROW 51104, 'Profile metadata differs. Use a new ProfileName; never mix different models.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.EmbeddingProfiles WHERE ProfileName = @Name)
    INSERT dbo.EmbeddingProfiles
        (ProfileName, Provider, ModelName, ModelVersion, Dimensions, DocumentPrefix, QueryPrefix)
    VALUES (@Name, 'Ollama', @Model, @Digest, 768, N'search_document: ', N'search_query: ');
SELECT ProfileId FROM dbo.EmbeddingProfiles WHERE ProfileName = @Name;
'@
    $profileId = [int]$profileRow.Rows[0].ProfileId

    foreach ($kind in @('Cases', 'Queries')) {
        if ($kind -eq 'Cases') {
            $pendingSql = @'
SELECT i.CaseId AS Id, CONCAT(p.DocumentPrefix, i.InputText) AS InputText,
    HASHBYTES('SHA2_256', CONCAT(p.DocumentPrefix, i.InputText)) AS InputHash
FROM dbo.CaseEmbeddingInputs AS i
CROSS JOIN dbo.EmbeddingProfiles AS p
LEFT JOIN dbo.CaseEmbeddings AS e ON e.CaseId = i.CaseId AND e.ProfileId = p.ProfileId
WHERE p.ProfileId = @ProfileId
  AND (e.EmbeddingId IS NULL OR e.InputHash <> HASHBYTES('SHA2_256', CONCAT(p.DocumentPrefix, i.InputText)))
ORDER BY i.CaseId;
'@
            $saveSql = @'
MERGE dbo.CaseEmbeddings AS t
USING (SELECT @ProfileId AS ProfileId, @Id AS CaseId) AS s
ON t.ProfileId = s.ProfileId AND t.CaseId = s.CaseId
WHEN MATCHED THEN UPDATE SET Embedding = CAST(@Vector AS vector(768)),
    InputHash = @Hash, PreparedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (ProfileId, CaseId, Embedding, InputHash)
    VALUES (@ProfileId, @Id, CAST(@Vector AS vector(768)), @Hash);
'@
        } else {
            $pendingSql = @'
SELECT s.PreparedSearchId AS Id, CONCAT(p.QueryPrefix, s.SearchText) AS InputText,
    HASHBYTES('SHA2_256', CONCAT(p.QueryPrefix, s.SearchText)) AS InputHash
FROM dbo.PreparedSearches AS s
CROSS JOIN dbo.EmbeddingProfiles AS p
LEFT JOIN dbo.QueryEmbeddings AS e ON e.PreparedSearchId = s.PreparedSearchId AND e.ProfileId = p.ProfileId
WHERE p.ProfileId = @ProfileId
  AND (e.ProfileId IS NULL OR e.InputHash <> HASHBYTES('SHA2_256', CONCAT(p.QueryPrefix, s.SearchText)))
ORDER BY s.PreparedSearchId;
'@
            $saveSql = @'
MERGE dbo.QueryEmbeddings AS t
USING (SELECT @ProfileId AS ProfileId, @Id AS PreparedSearchId) AS s
ON t.ProfileId = s.ProfileId AND t.PreparedSearchId = s.PreparedSearchId
WHEN MATCHED THEN UPDATE SET Embedding = CAST(@Vector AS vector(768)),
    InputHash = @Hash, PreparedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (ProfileId, PreparedSearchId, Embedding, InputHash)
    VALUES (@ProfileId, @Id, CAST(@Vector AS vector(768)), @Hash);
'@
        }
        $pending = Invoke-SetupQuery -Rows -Query $pendingSql -Parameters @{ ProfileId = $profileId }
        Write-Host "$kind needing embeddings: $($pending.Rows.Count)."
        for ($offset = 0; $offset -lt $pending.Rows.Count; $offset += $BatchSize) {
            $last = [Math]::Min($offset + $BatchSize, $pending.Rows.Count)
            $inputs = @($pending.Rows[$offset..($last - 1)] | ForEach-Object { $_.InputText })
            $response = Invoke-RestMethod -Uri http://localhost:11434/api/embed -Method Post `
                -ContentType 'application/json' -TimeoutSec 300 -Body (@{
                    model = $EmbeddingModel; input = $inputs; truncate = $false; keep_alive = '30m'
                } | ConvertTo-Json -Compress)
            Assert-OllamaEmbeddingBatch -Response $response -Count $inputs.Count -Dimensions 768
            for ($i = 0; $i -lt $inputs.Count; $i++) {
                $row = $pending.Rows[$offset + $i]
                Invoke-SetupQuery -Query $saveSql -Parameters @{
                    ProfileId = $profileId; Id = [int]$row.Id; Hash = [byte[]]$row.InputHash
                    Vector = ConvertTo-Json -InputObject $response.embeddings[$i] -Compress
                }
            }
            Write-Host "$kind embeddings prepared: $last/$($pending.Rows.Count)."
        }
    }
    Invoke-SetupScript '06-create-vector-index.sql'
    Invoke-SetupQuery -Parameters @{ ProfileId = $profileId } -Query @'
IF EXISTS
(
    SELECT 1 FROM dbo.CaseEmbeddingInputs AS i CROSS JOIN dbo.EmbeddingProfiles AS p
    LEFT JOIN dbo.CaseEmbeddings AS e ON e.ProfileId = p.ProfileId AND e.CaseId = i.CaseId
    WHERE p.ProfileId = @ProfileId
      AND (e.EmbeddingId IS NULL OR e.InputHash <> HASHBYTES('SHA2_256', CONCAT(p.DocumentPrefix, i.InputText)))
) OR EXISTS
(
    SELECT 1 FROM dbo.PreparedSearches AS s CROSS JOIN dbo.EmbeddingProfiles AS p
    LEFT JOIN dbo.QueryEmbeddings AS e ON e.ProfileId = p.ProfileId AND e.PreparedSearchId = s.PreparedSearchId
    WHERE p.ProfileId = @ProfileId
      AND (e.ProfileId IS NULL OR e.InputHash <> HASHBYTES('SHA2_256', CONCAT(p.QueryPrefix, s.SearchText)))
)
    THROW 51104, 'Embedding set is incomplete or source text changed during preparation. Rerun setup.', 1;
UPDATE dbo.DemoConfiguration SET ActiveProfileId = @ProfileId WHERE ConfigurationId = 1;
'@
    Invoke-SetupScript '07-verify-data.sql'
    Write-Host 'CustomerServiceDesk database build and verification passed. No web application was started.'
} finally {
    $connection.Dispose()
    $securePassword.Dispose()
}
