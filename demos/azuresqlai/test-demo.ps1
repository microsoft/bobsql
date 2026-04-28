# test-demo.ps1 - Run test queries against the Azure SQL AI demo
# Exercises the vector search and RAG chat completion stored procedures.
#
# Prerequisites:
#   1. Run deploy.ps1 to create Azure resources
#   2. Run run-demo.ps1 to set up the database objects and data

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
Write-Host "  Azure SQL AI Demo - Test Queries" -ForegroundColor Green
Write-Host "  Server  : $serverFQDN" -ForegroundColor Yellow
Write-Host "  Database: $sqlDatabaseName" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Green

# --- Vector Search Tests ---

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  VECTOR SEARCH TESTS (usp_vector_search)" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

Invoke-DemoQuery -Title "Test 1: Security features" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'What security features protect my data?';"

Invoke-DemoQuery -Title "Test 2: AI and machine learning capabilities" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'How can I use AI and machine learning with my database?';"

Invoke-DemoQuery -Title "Test 3: Disaster recovery (top 3)" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'What options are available for disaster recovery?', @top_n = 3;"

Invoke-DemoQuery -Title "Test 4: Serverless and auto-scaling" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'Tell me about serverless and auto-scaling';"

Invoke-DemoQuery -Title "Test 5: AI agents and MCP" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'How can AI agents query my database safely?';"

Invoke-DemoQuery -Title "Test 6: Generating embeddings in T-SQL" `
    -Query "EXEC dbo.usp_vector_search @search_text = N'How do I generate embeddings in T-SQL?';"

# --- RAG Chat Completion Tests ---

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  RAG CHAT TESTS (usp_chat_with_data)" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

Invoke-DemoQuery -Title "Chat 1: Security - encryption vs masking" `
    -Query "EXEC dbo.usp_chat_with_data @user_question = N'What security features does Azure SQL Database offer to protect sensitive data? Compare encryption and masking options.';"

Invoke-DemoQuery -Title "Chat 2: AI-powered applications" `
    -Query "EXEC dbo.usp_chat_with_data @user_question = N'How can I build an AI-powered application using Azure SQL Database? What vector search and embedding capabilities are available?';"

Invoke-DemoQuery -Title "Chat 3: High availability and DR" `
    -Query "EXEC dbo.usp_chat_with_data @user_question = N'What are my options for ensuring high availability and disaster recovery with Azure SQL Database?';"

Invoke-DemoQuery -Title "Chat 4: Slow query performance tuning" `
    -Query "EXEC dbo.usp_chat_with_data @user_question = N'My queries are running slow. What automatic performance tuning features can help without changing my application code?';"

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "  All tests completed!" -ForegroundColor Green
Write-Host "======================================================`n" -ForegroundColor Green
