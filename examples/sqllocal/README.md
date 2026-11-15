# Caldova Regional Care: SQL Server and local AI

A synthetic regional transfer-center demo using SQL Server 2025, an ASP.NET
Core 10 app, and Foundry Local models on AKS on Azure Local. SQL owns JSON
grounding packets, approved prompt contracts, model calls, optional vector
retrieval, response validation, saved citations, and append-only ledger audit.
An optional Azure SQL Database Hyperscale / Microsoft Foundry variant is included.

**Demo only.** Records and historical notes are synthetic. Generated text is
for demonstration and human review, not diagnosis, treatment, or clinical use.
The web app has no authentication or authorization layer: keep it on an
isolated lab machine. Do not expose it publicly or load real patient data.

## Start here

| Folder | Contents |
| --- | --- |
| [app](app/README.md) | Live database-backed transfer-center application |
| [database](database/README.md) | Ordered schema, synthetic seed, AI, vector, and verification scripts |
| [setup](setup/README.md) | Windows prerequisites, existing gateway trust, ingress, and model tests |
| [hyperscale-foundry](hyperscale-foundry/README.md) | Optional billable Azure SQL + Foundry deployment |
| [architecture](architecture/README.md) | Offline architecture player and regeneratable presentation sources |

[DEMO-RUNBOOK.md](DEMO-RUNBOOK.md) describes the presentation sequence.
[Publish-Demo.ps1](Publish-Demo.ps1) copies source to an empty destination;
it is not a secret scrubber or a deployment command.

## Before running: configure your own environment

This public copy deliberately contains no working lab coordinates or credentials.

| Example value | Meaning / action |
| --- | --- |
| `192.0.2.10` | Reserved documentation IP (TEST-NET-1), not a reachable gateway. Replace consistently as described below. |
| `C:\setup\caldova-admin.kubeconfig` | Example local path. Keep your real kubeconfig outside the checkout; pass `-KubeconfigPath`. |
| `caldova-model-lb` | Example MetalLB pool/advertisement name; align the manifest and ingress wrapper with your cluster. |
| `caldova-aks`, `rg-caldova-local` | Example Arc cluster/resource group names, not provisioned resources. |
| `your-unique-sql-server`, `your-unique-foundry-resource` | Choose your own globally unique Azure names for the cloud variant. |
| `localhost`, `CaldovaRegionalCare` | Local SQL instance and fixed demo database name; instance overrides are supported. |

Keep the namespace `foundry-local-operator`, model deployments
`gpt-oss-20b` (chat) and `nemotron-3-embed-1b-bf16` (embeddings), their
`<deployment>-api-keys` secrets, and gateway TLS secret
`inference-external-gateway-ip-tls` aligned with your existing installation.
These are expected resource contracts, not secret values.

Search this collection for **`192.0.2.10`** before running. Replace it in:

- The defaults in setup/model/database PowerShell scripts, or pass their
  `-ExternalIPAddress` parameter where available.
- [caldova-model-ingress.yaml](setup/caldova-model-ingress.yaml) and
  [Restore-FoundryIngress.ps1](setup/Restore-FoundryIngress.ps1), including the
  MetalLB name in both.
- [04-external-model.sql](database/04-external-model.sql) and both
  [isolated model tests](database/model-tests/README.md). Their credential
  names and endpoint URLs must match the credentials created by PowerShell.

The gateway certificate must cover your actual IP in its subject alternative
names and be trusted by Windows and SQL Server. Do not bypass TLS verification.
Changing only the browser or app connection string does not change SQL's model
endpoint or embedding model.

## Prerequisites

For the local AI path:

- A Windows machine with SQL Server 2025, .NET 10 SDK, and PowerShell 7.
- `sqlcmd`, `curl.exe`, `kubectl`, and a protected kubeconfig with access to
  the required namespace, model resources, and secrets.
- Windows integrated SQL administrator access for setup; local administrator
  access for installing prerequisites and importing the gateway root CA.
- An existing Azure Local system, AKS cluster, Foundry Local installation,
  ready model deployments, authenticated HTTPS gateway, and network access.
- A SQL Server build supporting the included preview features for the optional
  `VECTOR(2048, float16)` and approximate vector index examples.
- VS Code's MSSQL extension or SSMS to inspect and execute SQL.

The kit does **not** provision Azure Local, AKS, the Foundry Local extension,
models, MetalLB, or certificates. Start with Microsoft's guides for
[Azure Local](https://learn.microsoft.com/azure/azure-local/deploy/deployment-introduction),
[AKS on Azure Local](https://learn.microsoft.com/azure/aks/aksarc/aks-overview),
and [Foundry Local on Azure Local](https://learn.microsoft.com/azure/azure-sovereign-clouds/private/foundry-local/deploy-foundry-local-arc-extension).

## 1. Prepare trust and test the gateway

Read [setup/README.md](setup/README.md) first. In an elevated PowerShell window,
from this collection's root:

```powershell
.\setup\Setup.ps1 -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig'
```

This can install software, import a root into `LocalMachine\Root`, and
**restart SQL Server and its running dependent services**. Review the root
certificate with your infrastructure owner first.

For an explicit SQL-to-chat smoke test using the current chat deployment:

```powershell
.\setup\test.ps1 -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' `
    -DeploymentName 'gpt-oss-20b' -ExternalIPAddress '<your-gateway-ip>'
```

This enables server-level external REST access and creates credentials and
procedures in `tempdb` by default. A successful HTTPS probe alone does not prove
SQL can invoke the model. The script's legacy default deployment is
`phi-35-mini`; the command above overrides it.

## 2. Initialize the application database

After replacing the example IPs:

```powershell
.\database\Setup-CaldovaDatabase.ps1 -InitializeDatabase `
    -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' `
    -ExternalIPAddress '<your-gateway-ip>'
```

The wrapper refuses initialization if `CaldovaRegionalCare` already exists.
It creates schema and synthetic data, installs ledger/helpers, checks packets,
discovers the served chat model, configures its encrypted credential, and
installs RAG procedures. It does **not** install the optional vector layer or
run a live briefing test unless `-TestFoundryAi` is supplied.

For an existing database, omit `-InitializeDatabase` to refresh repeat-safe
objects. Use `-ConfigureModelOnly` to change only the active chat endpoint.
Both still require your kubeconfig and gateway IP.

## 3. Optionally add historical vector search

The initializer and SQL files must all use the same gateway IP. From this root:

```powershell
.\setup\Initialize-FoundrySqlTests.ps1 -ApplicationVectorSearch `
    -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig'
sqlcmd -S localhost -E -C -b -i .\database\04-external-model.sql .\database\05-vector-embeddings.sql .\database\06-vector-search.sql .\database\07-rag.sql
.\database\Test-CaldovaVectorHistory.ps1
```

The initializer enables `PREVIEW_FEATURES` in the user database and creates
the encrypted embedding credential. Script `05` is **first-install only**:
it creates the vector table, generates passage-prefixed embeddings, and builds
the cosine DiskANN index. Later use `ai.usp_RefreshHistoricalNoteEmbeddings`
from script `06`, not a rerun of script `05`.

Search is restricted to the same patient's notes dated before the transfer.
Missing/stale embeddings and a missing index fail explicitly. The demo's
distance thresholds are retrieval filters, not clinical confidence scores.
Changing embedding models requires compatible vectors and indexes to be rebuilt.

## 4. Build and run the app

```powershell
dotnet build .\app\Caldova.TransferCenter.csproj
.\app\run.ps1
```

Open `http://localhost:5099`. Check `http://localhost:5099/api/health` for
`Healthy` and `CaldovaRegionalCare`; health checks SQL connectivity, not model
readiness. The default uses Windows integrated SQL authentication.
See [app/README.md](app/README.md) for connection overrides and API behavior.

**Find relevant history** is a standalone preview. **Generate receiving
briefing** invokes SQL-owned generation; **Include relevant history (top 3)**
independently enables retrieval using the transfer concern. Saved citations
refer to source snapshots, not subsequently edited notes. The Audit overlay
shows completed interactions recorded in the append-only SQL ledger.
External database digest storage/verification is **not configured**.

## Verification and optional cloud deployment

See [database/README.md](database/README.md) for the packet, live briefing,
vector, RAG, and ledger tests and their side effects. These are integration
tests against your configured lab, not offline unit tests. Do not run them
against production or assume the public example values have been validated
against your infrastructure.

For Azure SQL Hyperscale and Microsoft Foundry, follow the separate
[cloud README](hyperscale-foundry/README.md). It provisions billable resources
and uses Entra authentication / managed identity rather than a model API key.
It does not deploy the local Nemotron vector path.

## Secrets and publication

- Supply credentials at runtime. Never commit kubeconfigs, API keys, private
  keys, database backups, connection strings containing passwords, or real data.
- Setup retrieves model keys from Kubernetes into process memory and stores
  them in encrypted database-scoped credentials; no literal key is required.
- Generated database master-key passwords are not retained for recovery:
  arrange key backup/recovery before using a database beyond a disposable lab.
- The local SQL examples use `-C` / `TrustServerCertificate=true` for lab SQL
  certificates. Use properly validated SQL certificates outside the lab.
- [.gitignore](.gitignore) excludes common local credentials, build output,
  certificates, and generated media. Ignore rules are not secret detection.
- Generated PNG/PPTX/MP4 assets and build caches are deliberately absent.
  Regenerate presentation assets from [architecture](architecture/README.md).
- Before publishing, run the destination repository's
  [secret-scanning procedure](../../SECRET-SCANNING.md), review every new file,
  and rotate any credential ever committed. A passing scan is not certification.

Keep all actual environment overrides private. This sanitized copy is
independent of the original presentation kit.
