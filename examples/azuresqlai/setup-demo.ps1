# setup-demo.ps1 - Execute all Azure SQL AI demo scripts against the database
# Uses Invoke-Sqlcmd with an Azure CLI access token for Entra authentication.
#
# Prerequisites:
#   1. Run deploy.ps1 first to create Azure resources
#   2. PowerShell SqlServer module: Install-Module SqlServer
#   3. Be logged into Azure CLI: az login

param(
    [string]$sqlServerName = "sqlserver-sqlai-demo",
    [string]$sqlDatabaseName = "sqldb-sqlai-demo"
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot

# Build the FQDN for the server
$serverFQDN = "$sqlServerName.database.windows.net"

# Ensure the SqlServer module is available
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "Installing SqlServer PowerShell module..." -ForegroundColor Yellow
    Install-Module SqlServer -Scope CurrentUser -Force -AllowClobber
}
Import-Module SqlServer -ErrorAction Stop

# Get an access token from Azure CLI for Azure SQL Database
Write-Host "`nGetting access token from Azure CLI..." -ForegroundColor Gray
$accessToken = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv
if (-not $accessToken) {
    Write-Host "ERROR: Failed to get access token. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# Function to execute a SQL script file against the database
function Invoke-DemoScript {
    param(
        [string]$ScriptFile,
        [string]$Description
    )
    
    $filePath = Join-Path $scriptDir $ScriptFile
    if (-not (Test-Path $filePath)) {
        Write-Host "ERROR: Script not found: $filePath" -ForegroundColor Red
        exit 1
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Description" -ForegroundColor Cyan
    Write-Host "  File: $ScriptFile" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan

    # Read the file and split on GO batch separators
    $scriptContent = Get-Content $filePath -Raw
    $batches = $scriptContent -split '(?m)^\s*GO\s*$' | Where-Object { $_.Trim() -ne '' }

    $batchNum = 0
    foreach ($batch in $batches) {
        $batchNum++
        Invoke-Sqlcmd -ServerInstance $serverFQDN -Database $sqlDatabaseName `
            -AccessToken $accessToken -Query $batch `
            -QueryTimeout 120 -ErrorAction Stop
    }

    Write-Host "  DONE ($batchNum batches)" -ForegroundColor Green
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "  Azure SQL AI Demo - Running all scripts" -ForegroundColor Green
Write-Host "  Server  : $serverFQDN" -ForegroundColor Yellow
Write-Host "  Database: $sqlDatabaseName" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Green

# Step 1: Create external model, credential, and master key
Invoke-DemoScript -ScriptFile "01-setup-external-model.sql" `
    -Description "Step 1/7: Setup external model and credentials"

# Step 2: Create knowledge base table and insert 110 rows
Invoke-DemoScript -ScriptFile "02-create-table-with-data.sql" `
    -Description "Step 2/7: Create table and insert sample data (110 rows)"

# Step 3: Generate embeddings for all rows (calls Azure OpenAI)
Invoke-DemoScript -ScriptFile "03-generate-embeddings.sql" `
    -Description "Step 3/7: Generate embeddings (calls Azure OpenAI - may take a moment)"

# Step 4: Create DiskANN vector index
Invoke-DemoScript -ScriptFile "04-create-vector-index.sql" `
    -Description "Step 4/7: Create DiskANN vector index and verify"

# Step 5: Create vector search stored procedure and test
Invoke-DemoScript -ScriptFile "05-vector-search-sp.sql" `
    -Description "Step 5/7: Create vector search stored procedure"

# Step 6: Add new rows with inline embeddings and search
Invoke-DemoScript -ScriptFile "06-add-rows-and-search.sql" `
    -Description "Step 6/7: Add new rows and search for them"

# Step 7: Create RAG chat completion stored procedure and test
Invoke-DemoScript -ScriptFile "07-chat-completion-sp.sql" `
    -Description "Step 7/7: Create RAG chat completion procedure and test"

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "  All demo scripts completed successfully!" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Run .\run-demo.ps1 to exercise the demo." -ForegroundColor Yellow
