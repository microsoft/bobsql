# run-demo.ps1 - Run the Azure SQL AI demo
# Demonstrates vector search, inserting new rows, and RAG chat completion.
#
# Prerequisites:
#   1. Run deploy.ps1 to create Azure resources
#   2. Run setup-demo.ps1 to set up the database objects and data

param(
    [string]$sqlServerName = "sqlserver-sqlai-demo",
    [string]$sqlDatabaseName = "sqldb-sqlai-demo"
)

$ErrorActionPreference = "Stop"
$serverFQDN = "$sqlServerName.database.windows.net"

# Ensure SqlServer module
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "Installing SqlServer PowerShell module..." -ForegroundColor Yellow
    Install-Module SqlServer -Scope CurrentUser -Force -AllowClobber
}
Import-Module SqlServer -ErrorAction Stop

# Get access token
Write-Host "`nGetting access token from Azure CLI..." -ForegroundColor Gray
$accessToken = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv
if (-not $accessToken) {
    Write-Host "ERROR: Failed to get access token. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# Helper to run a query and display results
function Invoke-DemoQuery {
    param(
        [string]$Title,
        [string]$Query
    )

    Write-Host "`n----------------------------------------" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan

    $results = Invoke-Sqlcmd -ServerInstance $serverFQDN -Database $sqlDatabaseName `
        -AccessToken $accessToken -Query $Query -QueryTimeout 120 -ErrorAction Stop

    if ($results) {
        $results | Format-List
    }
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "  Azure SQL AI Demo" -ForegroundColor Green
Write-Host "  Server  : $serverFQDN" -ForegroundColor Yellow
Write-Host "  Database: $sqlDatabaseName" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Green

# --- Step 1: Vector Search with TOP WITH APPROXIMATE ---

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  STEP 1: Vector Search (TOP WITH APPROXIMATE)" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

Invoke-DemoQuery -Title "Search: 'What security features protect my data?'" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'What security features protect my data?';"

Invoke-DemoQuery -Title "Search: 'How can I use AI with my database?'" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'How can I use AI and machine learning with my database?';"

Invoke-DemoQuery -Title "Search: 'disaster recovery options' (top 3)" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'What options are available for disaster recovery?', @top_n = 3;"

# --- Step 2: Insert new rows and search for them ---

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  STEP 2: Insert New Rows and Search" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

Invoke-DemoQuery -Title "Row count before insert" `
    -Query "SELECT COUNT(*) AS total_rows FROM dbo.azure_sql_knowledge;"

Invoke-DemoQuery -Title "Insert new row about SQL MCP Server with inline embedding" `
    -Query "IF NOT EXISTS (SELECT 1 FROM dbo.azure_sql_knowledge WHERE title = N'SQL MCP Server for AI Agents')
INSERT INTO dbo.azure_sql_knowledge (title, category, content, embedding)
VALUES (N'SQL MCP Server for AI Agents', N'AI and Machine Learning',
N'SQL MCP Server provides a stable and governed interface for AI agents to interact with Azure SQL databases. The Model Context Protocol (MCP) enables AI agents to discover available capabilities, understand inputs and outputs, and operate without guessing.',
AI_GENERATE_EMBEDDINGS(N'SQL MCP Server provides a stable and governed interface for AI agents to interact with Azure SQL databases. The Model Context Protocol (MCP) enables AI agents to discover available capabilities, understand inputs and outputs, and operate without guessing.' USE MODEL EmbeddingModel));
SELECT COUNT(*) AS total_rows FROM dbo.azure_sql_knowledge;"

Invoke-DemoQuery -Title "Search for the new row: 'How can AI agents query my database?'" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'How can AI agents query my database safely?', @top_n = 3;"

# --- Step 3: RAG Chat Completion ---

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  STEP 3: RAG Chat Completion" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

Invoke-DemoQuery -Title "Chat: 'What security features does Azure SQL offer?'" `
    -Query "EXEC dbo.usp_chat_with_data @user_question = N'What security features does Azure SQL Database offer to protect sensitive data? Compare encryption and masking options.';"

Invoke-DemoQuery -Title "Chat: 'How can I build an AI app with Azure SQL?'" `
    -Query "EXEC dbo.usp_chat_with_data @user_question = N'How can I build an AI-powered application using Azure SQL Database? What vector search and embedding capabilities are available?';"

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "  Demo completed!" -ForegroundColor Green
Write-Host "======================================================`n" -ForegroundColor Green
