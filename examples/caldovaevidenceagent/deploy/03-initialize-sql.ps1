[CmdletBinding()]
param(
    [ValidateRange(1, 100)][int]$BatchSize = 25
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

$python = Get-PythonCommand
$databaseScript = Join-Path $PSScriptRoot '..\database\deploy_database.py'
$foundry = Invoke-AzJson @('cognitiveservices', 'account', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $FoundryAccountName, '--output', 'json')

Write-Step 'Python dependencies'
& $python -c 'import pyodbc; print("    pyodbc " + pyodbc.version)'
if ($LASTEXITCODE -ne 0) {
    throw "pyodbc is unavailable. Run: python -m pip install -r $((Join-Path $PSScriptRoot '..\requirements.txt'))"
}

Write-Step 'Schema, corpus, native embeddings, DiskANN, and retrieval procedures'
& $python $databaseScript `
    --subscription $ExpectedSubscriptionId `
    --server "$SqlServerName.database.windows.net" `
    --database $DatabaseName `
    --foundry-endpoint $foundry.properties.endpoint `
    --embedding-deployment $EmbeddingDeploymentName `
    --corpus $CorpusPath `
    --batch-size $BatchSize
if ($LASTEXITCODE -ne 0) { throw "Database initialization failed with exit code $LASTEXITCODE." }

Write-Host "`nSQL initialization complete. Next: run 04-verify-sql.ps1." -ForegroundColor Green
