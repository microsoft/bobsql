# deploy.ps1 - Deploy Azure resources for Azure SQL AI demo
# Creates: Resource Group, Azure OpenAI (with embedding + chat models),
#          Azure SQL Database (GP Serverless, Entra-only auth, system-assigned MI)
#
# NOTE: Azure OpenAI resource names must be alphanumeric and hyphens only (no underscores).
#       Custom subdomain (--custom-domain) is required for managed identity auth.
#       Only one free-tier Azure SQL database is allowed per subscription.
#       --identity-type SystemAssigned does NOT work during az sql server create
#       with --enable-ad-only-auth; must use separate az sql server update --assign_identity.
#       Check model/version availability in your region before deploying.

param(
    [string]$subscriptionId = "0efc44aa-c965-420f-aac4-fff305dbcc97",
    [string]$resourceGroup = "rg-azursqlai-demo",
    [string]$location = "eastus",
    [string]$aoaiName = "aoai-sqlai-demo",
    [string]$embeddingModelName = "text-embedding-ada-002",
    [string]$embeddingModelVersion = "2",
    [string]$chatModelName = "gpt-4.1-mini",
    [string]$chatModelVersion = "2025-04-14",
    [string]$sqlServerName = "sqlserver-sqlai-demo",
    [string]$sqlDatabaseName = "sqldb-sqlai-demo"
)

$ErrorActionPreference = "Stop"

# Set the subscription
Write-Host "`n=== Setting subscription ===" -ForegroundColor Cyan
az account set --subscription $subscriptionId

# Create resource group
Write-Host "`n=== Creating resource group: $resourceGroup ===" -ForegroundColor Cyan
az group create --name $resourceGroup --location $location --output table

# Create Azure OpenAI resource
Write-Host "`n=== Creating Azure OpenAI resource: $aoaiName ===" -ForegroundColor Cyan
az cognitiveservices account create `
    --name $aoaiName `
    --resource-group $resourceGroup `
    --location $location `
    --kind OpenAI `
    --sku S0 `
    --custom-domain $aoaiName `
    --output table

# Deploy embedding model
Write-Host "`n=== Deploying embedding model: $embeddingModelName ===" -ForegroundColor Cyan
az cognitiveservices account deployment create `
    --name $aoaiName `
    --resource-group $resourceGroup `
    --deployment-name $embeddingModelName `
    --model-name $embeddingModelName `
    --model-version $embeddingModelVersion `
    --model-format OpenAI `
    --sku-capacity 30 `
    --sku-name Standard `
    --output table

# Deploy chat completion model
Write-Host "`n=== Deploying chat model: $chatModelName ===" -ForegroundColor Cyan
az cognitiveservices account deployment create `
    --name $aoaiName `
    --resource-group $resourceGroup `
    --deployment-name $chatModelName `
    --model-name $chatModelName `
    --model-version $chatModelVersion `
    --model-format OpenAI `
    --sku-capacity 30 `
    --sku-name Standard `
    --output table

# Get current signed-in user info for Entra admin
Write-Host "`n=== Getting current user info for Entra admin ===" -ForegroundColor Cyan
$userDisplayName = az ad signed-in-user show --query displayName -o tsv
$userObjectId = az ad signed-in-user show --query id -o tsv
Write-Host "Entra Admin: $userDisplayName ($userObjectId)"

# Create Azure SQL logical server (Entra-only, system-assigned managed identity)
Write-Host "`n=== Creating Azure SQL server: $sqlServerName (Entra-only auth) ===" -ForegroundColor Cyan
az sql server create `
    --name $sqlServerName `
    --resource-group $resourceGroup `
    --location $location `
    --enable-ad-only-auth `
    --external-admin-principal-type User `
    --external-admin-name $userDisplayName `
    --external-admin-sid $userObjectId `
    --output table

# Assign system-assigned managed identity (must be done separately after server create)
Write-Host "`n=== Assigning system-assigned managed identity to SQL server ===" -ForegroundColor Cyan
az sql server update `
    --name $sqlServerName `
    --resource-group $resourceGroup `
    --assign_identity `
    --identity-type SystemAssigned `
    --output table

# Add firewall rule to allow Azure services
Write-Host "`n=== Adding firewall rule for Azure services ===" -ForegroundColor Cyan
az sql server firewall-rule create `
    --resource-group $resourceGroup `
    --server $sqlServerName `
    --name AllowAzureServices `
    --start-ip-address 0.0.0.0 `
    --end-ip-address 0.0.0.0 `
    --output table

# Add firewall rule for client IP
Write-Host "`n=== Adding firewall rule for client IP ===" -ForegroundColor Cyan
$clientIp = (Invoke-RestMethod -Uri "https://api.ipify.org")
Write-Host "Client IP: $clientIp"
az sql server firewall-rule create `
    --resource-group $resourceGroup `
    --server $sqlServerName `
    --name AllowClientIP `
    --start-ip-address $clientIp `
    --end-ip-address $clientIp `
    --output table

# Create Azure SQL Database (GP Serverless)
Write-Host "`n=== Creating Azure SQL Database: $sqlDatabaseName (GP Serverless) ===" -ForegroundColor Cyan
az sql db create `
    --resource-group $resourceGroup `
    --server $sqlServerName `
    --name $sqlDatabaseName `
    --edition GeneralPurpose `
    --compute-model Serverless `
    --family Gen5 `
    --capacity 2 `
    --auto-pause-delay 60 `
    --max-size 32GB `
    --output table

# Assign Cognitive Services OpenAI User role to SQL server managed identity
Write-Host "`n=== Assigning Cognitive Services OpenAI User role to SQL server MI ===" -ForegroundColor Cyan
$sqlServerMI = az sql server show `
    --name $sqlServerName `
    --resource-group $resourceGroup `
    --query identity.principalId -o tsv

$aoaiResourceId = az cognitiveservices account show `
    --name $aoaiName `
    --resource-group $resourceGroup `
    --query id -o tsv

az role assignment create `
    --assignee $sqlServerMI `
    --role "Cognitive Services OpenAI User" `
    --scope $aoaiResourceId `
    --output table

# Get the Azure OpenAI endpoint
$aoaiEndpoint = az cognitiveservices account show `
    --name $aoaiName `
    --resource-group $resourceGroup `
    --query properties.endpoint -o tsv

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Deployment complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Azure OpenAI Endpoint : $aoaiEndpoint" -ForegroundColor Yellow
Write-Host "Azure OpenAI Name     : $aoaiName" -ForegroundColor Yellow
Write-Host "Embedding Deployment  : $embeddingModelName" -ForegroundColor Yellow
Write-Host "Chat Deployment       : $chatModelName" -ForegroundColor Yellow
Write-Host "SQL Server            : $sqlServerName.database.windows.net" -ForegroundColor Yellow
Write-Host "SQL Database          : $sqlDatabaseName" -ForegroundColor Yellow
Write-Host "SQL Server MI         : $sqlServerMI" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. In SQL script 01, set @AoaiName variable to: $aoaiName" -ForegroundColor White
Write-Host "  2. Connect to $sqlServerName.database.windows.net / $sqlDatabaseName" -ForegroundColor White
Write-Host "  3. Run scripts 01 through 07 in order" -ForegroundColor White
Write-Host "  Note: Script 07 proc accepts @aoai_name parameter (default: $aoaiName)" -ForegroundColor White
