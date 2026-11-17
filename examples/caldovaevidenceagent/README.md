# Caldova Evidence Agent

A portable companion repository for building and presenting a biomedical evidence agent on Azure.

The system combines:

- Azure SQL Database Hyperscale with native embeddings and DiskANN vector search
- Data API builder SQL MCP Server with exactly three governed stored-procedure tools
- A Microsoft Foundry hosted .NET agent using GPT-5
- A formal, versioned Foundry Agent Skill
- A React and Express application hosted on Azure App Service

The curated public corpus contains 30 CC BY-licensed PubMed Central open access articles and 2,834 passages. It contains no patient data and no precomputed vectors; deployment generates fresh 512-dimensional embeddings inside Azure SQL. See [corpus attribution](../THIRD-PARTY-NOTICES.md) for article credits and licenses.

## Architecture

```text
Browser
  -> React/Express App Service
  -> Microsoft Foundry hosted .NET agent
       -> versioned biomedical-evidence-review skill
       -> GPT-5 directly chooses SQL MCP tools
  -> DAB SQL MCP Server in Azure Container Apps
  -> approved Azure SQL stored procedures
  -> Azure SQL Hyperscale + DiskANN + native embeddings
```

See `architecture.svg` for the complete diagram.

See [architecture animation](animation/README.md) for a reproducible 30-second,
silent 4K video with animated data flows and no captions.

## What Gets Deployed

- One resource group
- Azure SQL logical server and `research` Hyperscale serverless database
- Microsoft Foundry account, project, embedding deployment, and GPT-5 deployment
- Azure Container Registry
- Container Apps environment and DAB SQL MCP Container App
- Managed identities for DAB and the web app
- Foundry hosted agent and versioned skill
- Linux App Service plan, web app, Application Insights, and alert rule

These resources incur Azure charges. Review names, regions, quota, and subscription before approving the build.

## Prerequisites

Install and authenticate:

- PowerShell 7
- Azure CLI with the Container Apps extension
- Azure Developer CLI (`azd`) with the `microsoft.foundry` extension
- Python 3.11 or later
- Microsoft ODBC Driver 18 for SQL Server
- Node.js 22 and npm
- .NET 10 SDK
- Microsoft Edge for the standalone demo window

```powershell
az login
az account set --subscription "<subscription-id-or-name>"
azd auth login
azd extension install microsoft.foundry
```

Required Azure permissions include resource creation, role assignments, Azure SQL administration, model deployment, and Foundry agent deployment.

## Portable Configuration

The scripts use the current Azure CLI subscription and tenant by default. Override settings with process environment variables before running a stage:

```powershell
$env:CALDOVA_SUBSCRIPTION_ID = '<subscription-id>'
$env:CALDOVA_TENANT_ID = '<tenant-id>'
$env:CALDOVA_NAME_SUFFIX = 'demo123'
$env:CALDOVA_RESOURCE_GROUP = 'rg-caldova-evidence'
$env:CALDOVA_SQL_LOCATION = 'westcentralus'
$env:CALDOVA_FOUNDRY_LOCATION = 'eastus2'
$env:CALDOVA_APP_LOCATION = 'centralus'
$env:CALDOVA_AZD_ENVIRONMENT = 'caldova-evidence'
```

`CALDOVA_NAME_SUFFIX` must contain 3-10 lowercase letters or numbers. If omitted, the first six alphanumeric characters of the subscription ID are used.

Region and model quota availability varies. `deploy/01-preflight.ps1` measures the configured subscription before creating resources.

## Build Everything

Run from the repository root:

```powershell
.\deploy\Build-All.ps1
```

The build is staged and fail-fast:

1. Validate tools, Azure context, quota, regions, and corpus hashes.
2. Create Azure SQL, Foundry account, embedding deployment, and required identities.
3. Load the corpus, generate embeddings, create DiskANN, and deploy retrieval procedures.
4. Verify SQL counts, embeddings, index version, and retrieval.
5. Build and deploy DAB SQL MCP Server to Container Apps.
6. Verify MCP initialization, tool discovery, corpus status, and evidence search.
7. Create the Foundry project and GPT-5 deployment.
8. Publish the formal skill and deploy the hosted .NET agent.
9. Verify the hosted two-turn direct-MCP workflow.
10. Build and deploy the React/Express application to App Service.
11. Verify the complete browser-to-SQL path.

Each numbered script under `deploy/` can also be run independently for repair or diagnosis.

## Build Source Only

Without creating Azure resources:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
npm ci --prefix app
npm run build --prefix app
npm run lint --prefix app
npm audit --prefix app
dotnet build .\agent\hosted\caldova-evidence-hosted\src\foundry-toolbox-mcp-skills\foundry-toolbox-mcp-skills.csproj --configuration Release
```

## Run Locally

The app's Docker build uses `npm ci` to install the committed lockfile exactly.
The lockfile retains versions and integrity hashes without registry-specific
download URLs, so local feed settings are not required by container builds.
Dependency upgrades and successful local checks do not patch an existing Azure
deployment; rebuild, deploy, and verify authentication and agent calls separately.

After the hosted agent is deployed:

```powershell
.\run.ps1
```

To run against an existing hosted agent without local azd environment state, set:

```powershell
$env:CALDOVA_AGENT_ENDPOINT = 'https://<account>.services.ai.azure.com/api/projects/<project>/agents/caldova-evidence-hosted/endpoint/protocols/openai/responses?api-version=v1'
$env:CALDOVA_AGENT_VERSION = '<active-version>'
.\run.ps1
```

This script:

- Resolves the hosted-agent endpoint and version from explicit environment variables, local `azd` state, or deployed App Service settings
- Builds the application
- Starts Express on `http://127.0.0.1:8000`
- Opens the app in a standalone Microsoft Edge window and verifies that the visible `Caldova` window exists
- Writes local output under `.run/`

Stop it with:

```powershell
.\stop.ps1
```

## Run the Deployed App

`deploy/09-deploy-app-service.ps1` prints the deployed URL. By default it is:

```text
https://app-caldova-evidence-<suffix>.azurewebsites.net/
```

Check the deployed system at any time:

```powershell
.\deploy\11-verify-system.ps1
```

## Demo

Read `DEMO-RUNBOOK.md` before presenting. The live sequence is:

1. Open the Agent workspace.
2. Send the natural microbiome question.
3. Show three direct `search_evidence` calls in Foundry Log stream.
4. Read the five completed phases and visual evidence briefing.
5. Select **Find strongest causal evidence**.
6. Show the visual Strongest, Comparison, and Limitation response.
7. Close on the three-tool DAB SQL MCP boundary.

The `.github/skills/` directory provides discoverable build, run, and demo workflows for GitHub Copilot in VS Code.

## Security Boundary

DAB exposes exactly:

- `search_evidence`
- `get_article_context`
- `get_corpus_status`

REST, GraphQL, generic DML, writes, and arbitrary SQL are disabled. The DAB managed identity receives only the database permissions required by those procedures.

The provided demo deployment uses an anonymous public MCP endpoint over a public biomedical corpus. Before retaining it or using private data, enable Microsoft Entra authentication on the MCP endpoint and authorize only the hosted-agent identity.

## Verification Commands

```powershell
.\deploy\04-verify-sql.ps1
.\deploy\06-verify-dab-container-app.ps1
.\deploy\10-verify-hosted-agent.ps1 -EnvironmentName 'caldova-evidence'
.\deploy\11-verify-system.ps1
```

Replace `caldova-evidence` if you set `CALDOVA_AZD_ENVIRONMENT` to another name.

Expected initial response contract:

- Exactly three direct SQL MCP searches
- Exactly three distinct PMC sources
- Visual Bottom line, Evidence signals, Confidence, and Suggested follow-up sections
- High confidence for mechanistic plausibility with separate human-clinical qualification

Expected causal follow-up:

- Visual Strongest, Comparison, and Limitation signals
- Retained prior sources
- No unnecessary search when earlier evidence is sufficient

## Repository Layout

```text
.github/skills/   Copilot build, run, and demo workflows
agent/            Hosted .NET agent and formal Agent Skill
app/              React UI, Express API, Dockerfile, and App Service Bicep
dab/              DAB SQL MCP configuration and verifier
database/         SQL schema, retrieval procedures, loaders, and verification
corpus/           Text-only PMC corpus and integrity manifest
deploy/           Staged Azure deployment and verification scripts
DEMO-RUNBOOK.md   Presenter flow and recovery steps
run.ps1           Local app launcher
stop.ps1          Local app stop command
```

## Cleanup

For a short-lived demo, delete the dedicated resource group after recording:

```powershell
az group delete --name $env:CALDOVA_RESOURCE_GROUP --yes --no-wait
```

If `CALDOVA_RESOURCE_GROUP` was not set, the default is `rg-caldova-evidence`. Confirm the target resource group before running this destructive command.
