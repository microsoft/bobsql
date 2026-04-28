# Azure SQL AI Demo

This demo shows how to use Azure SQL Database's native AI capabilities including vector search, embeddings, and RAG (Retrieval Augmented Generation) chat completion — all from T-SQL using managed identity authentication.

## What It Does

1. Creates an external model connection to Azure OpenAI for embeddings
2. Builds a knowledge base table about Azure SQL Database features (110+ rows)
3. Generates vector embeddings using `AI_GENERATE_EMBEDDINGS`
4. Creates a DiskANN vector index for fast approximate nearest neighbor search
5. Creates a `usp_vector_search` stored procedure for semantic similarity search
6. Demonstrates adding new rows with inline embeddings (no index rebuild needed)
7. Creates a `usp_chat_with_data` RAG stored procedure that combines vector search with Azure OpenAI chat completion via `sp_invoke_external_rest_endpoint`

## Prerequisites

- **Azure subscription** with permissions to create resources
- **Azure CLI** (`az`): [Install](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **PowerShell 7+** with the **SqlServer** module (auto-installed by `setup-demo.ps1` if missing)
- **Azure OpenAI access** enabled on your subscription
- Logged in to Azure CLI: `az login`

## Files

| File | Description |
|------|-------------|
| `deploy.ps1` | Deploys all Azure resources (resource group, Azure OpenAI, Azure SQL Database, RBAC) |
| `setup-demo.ps1` | Executes all 7 SQL scripts in order against the database |
| `run-demo.ps1` | Runs the demo: shows table/index structure, vector search, and RAG chat |
| `01-setup-external-model.sql` | Creates master key, managed identity credential, and external model |
| `02-create-table-with-data.sql` | Creates knowledge base table and inserts 110 rows |
| `03-generate-embeddings.sql` | Generates embeddings for all rows via Azure OpenAI |
| `04-create-vector-index.sql` | Creates DiskANN vector index and verifies plan usage |
| `05-vector-search-sp.sql` | Creates and tests `usp_vector_search` stored procedure |
| `06-add-rows-and-search.sql` | Inserts new rows with inline embeddings and searches |
| `07-chat-completion-sp.sql` | Creates and tests `usp_chat_with_data` RAG stored procedure |

## Quick Start

### Step 1: Deploy Azure Resources

```powershell
cd demos\azuresqlai
.\deploy.ps1
```

This creates:
- Resource group: `rg-azursqlai-demo`
- Azure OpenAI resource: `aoai-sqlai-demo` with custom subdomain, `text-embedding-ada-002` and `gpt-4.1-mini` model deployments
- Azure SQL Database: `sqldb-sqlai-demo` on `sqlserver-sqlai-demo` (GP Serverless, 2 vCores, Entra-only auth)
- System-assigned managed identity on the SQL server
- `Cognitive Services OpenAI User` RBAC role assigned to the SQL server MI
- Firewall rules for Azure services and your client IP

### Step 2: Run the Demo Scripts

```powershell
.\setup-demo.ps1
```

Executes all 7 SQL scripts in order using `Invoke-Sqlcmd` with an Azure CLI access token for Entra authentication.

### Step 3: Run the Demo

```powershell
.\run-demo.ps1
```

Shows table structure, vector index details, runs approximate vector search with plan verification, and exercises the RAG chat completion.

## Using the Stored Procedures

After setup, connect to the database and run:

```sql
-- Semantic vector search
EXEC dbo.usp_vector_search @search_text = N'How do I scale my database?';
EXEC dbo.usp_vector_search @search_text = N'What security features are available?', @top_n = 3;

-- RAG chat completion (vector search + Azure OpenAI)
EXEC dbo.usp_chat_with_data @user_question = N'What are my options for disaster recovery?';
```

## Architecture

- **Authentication**: Managed identity (no API keys). The SQL server's system-assigned MI is granted `Cognitive Services OpenAI User` on the Azure OpenAI resource.
- **Embeddings**: `text-embedding-ada-002` (1536 dimensions) via `CREATE EXTERNAL MODEL` and `AI_GENERATE_EMBEDDINGS`
- **Vector Index**: DiskANN for approximate nearest neighbor search with cosine distance
- **Chat Completion**: `gpt-4.1-mini` called via `sp_invoke_external_rest_endpoint` with managed identity credential
- **RAG Pattern**: `usp_chat_with_data` generates an embedding for the user's question, finds the top-K most similar documents via vector search, then sends them as context to the chat model

## Customization

All three PowerShell scripts accept parameters to override default resource names:

```powershell
.\deploy.ps1 -sqlServerName "my-server" -aoaiName "my-aoai" -location "westus2"
.\setup-demo.ps1 -sqlServerName "my-server" -sqlDatabaseName "my-db"
.\run-demo.ps1 -sqlServerName "my-server" -sqlDatabaseName "my-db"
```

The SQL scripts use a `@AoaiName` variable (in script 01) and `@aoai_name` parameter (in script 07's stored procedure) that default to `aoai-sqlai-demo`. Update these if using a different Azure OpenAI resource name.

## Cleanup

Delete the resource group to remove all resources:

```powershell
az group delete --name rg-azursqlai-demo --yes --no-wait
```
