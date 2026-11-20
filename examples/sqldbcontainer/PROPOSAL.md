# Azure SQL Local-to-Cloud Application PoC

## Goal

Build a small .NET application against the Azure SQL development container,
then run the same application build against Azure SQL Database Hyperscale
serverless and deploy it to Azure App Service.

The application should demonstrate both familiar SQL capabilities and at least
one Azure SQL engine capability unavailable in SQL Server 2025.

This is a demo and portability PoC, not a live production migration. A brief
write freeze, offline database copy, and advance preparation are acceptable.
There is no requirement for replication, zero downtime, or live corpus embedding generation.

**Core message:** Develop locally with modern Azure SQL capabilities, then move
the application and database to Azure without rewriting application logic.

This document proposes the design; it does not claim the container features,
migration tooling, model deployments, or Azure resources have been verified.

Implementation update: the local database and .NET 10 Razor Pages application
are now built and verified; see [README.md](README.md) for reproducible scripts,
measured checks, restricted-identity setup, and known boundaries. Embedding
preparation uses the existing PowerShell/SqlClient runner rather than a separate
.NET utility. Azure migration, Foundry preparation, and App Service deployment
remain future work.
The Related cases page now also supports optional live local Ollama query
embeddings for user-entered questions, alongside the prepared dropdown. Both
paths use the same SQL vector retrieval; only the free-text path calls Ollama
at request time. Model digest, dimensions, and active profile are validated.

## Recommended application: Customer Service Desk

A compact customer-service workspace gives the features a coherent purpose:

- Browse approximately 1,000 synthetic support cases.
- Search by meaning to find related cases and previous resolutions.
- View flexible case details stored as native JSON.
- View customer contact information with database-enforced regex masking.
- Create or update a case locally and find that same record after the move.

Use synthetic customers, contact details, and case descriptions only.

### Main screens

| Screen | Experience | Database capability |
| --- | --- | --- |
| Case workspace | Browse cases, filter by status, open a case, and update it | Relational queries and ordinary DML |
| Related cases | Run a prepared semantic search and inspect matching resolutions | Native vectors and vector similarity search |
| Case details | Display product, channel, device, and issue-specific attributes | Native JSON storage, extraction, and filtering |
| Customer details | Show useful portions of contact fields while masking selected segments | Regex-based dynamic data masking |
| Environment panel | Show local/Azure target, build ID, embedding profile, and verified feature status | Measured configuration and diagnostics |

The environment panel must not display credentials, tokens, or full connection strings.

## Recommended .NET stack

**ASP.NET Core on .NET 10 LTS, Razor Pages, and Microsoft.Data.SqlClient,
published to a Windows Azure App Service.**

Confirm the selected App Service runtime and compatible package versions during
implementation. The container hosts the database only; the app initially runs
as a normal local .NET process.

| Layer | Recommendation | Reason |
| --- | --- | --- |
| UI | Razor Pages, CSS, and small amounts of JavaScript | Familiar .NET model, one deployable app, no separate Node build or SPA hosting |
| Application | Small C# services inside the web project | Keep business behavior identical across environments |
| Data access | Microsoft.Data.SqlClient with parameterized commands and stored procedures | Make the SQL features explicit without depending on ORM support for new features |
| Database definition | Versioned SQL scripts | Reviewable feature setup, repeatable seed, and explicit migration validation |
| Embedding preparation | Small .NET console utility, separate from request handling | Generate or regenerate vectors before the presentation |
| Configuration | ASP.NET Core configuration, local user secrets, App Service settings | Change endpoints and authentication without source edits |
| Hosting | Local Kestrel, then Windows App Service | Reuse a single Windows-targeted publish artifact; no custom app container required |

Publish once, test that publish output locally, and deploy that exact artifact.
Keep durable application state in SQL, not local files or in-memory session state.
Use browser-side requests for interactive search where needed, rather than a
permanent connection.

### Why not start with another stack?

- **Blazor Web App:** A good alternative for a strongly interactive C# UI and
  also deployable to App Service. Interactive Server adds circuit, reconnect,
  and hosting considerations that this PoC does not need.
- **React plus a .NET API:** Valid, but adds a frontend toolchain and another
  boundary without strengthening the database portability demonstration.
- **Aspire or multiple services:** Potentially useful later, but unnecessary
  orchestration for one app, one database, and offline embedding preparation.
- **EF Core:** Not excluded, but direct SqlClient access is clearer for a demo
  whose distinguishing behavior lives in new database features.

Razor Pages is a simplicity recommendation, not a claim that Blazor cannot
move to App Service.

## Feature selection

### 1. Regex-based dynamic data masking: primary differentiator

Define pattern-based masks on customer contact columns. For example, preserve a
useful email domain while obscuring the identifying portion.

The application reads the column normally. SQL applies the mask before returning
the result; the application does not implement a replacement regex mask.

- Use a restricted database principal without UNMASK or broad administrative permissions.
- Validate the actual application query path, including any stored procedure
  execution context, to prove masking is not bypassed.
- If an authorized/unmasked comparison is included, use a separately controlled
  database identity. A browser role selector alone must not grant UNMASK.
- Do not return an unmasked copy through JSON, search results, logs, or diagnostics.
- Masking limits accidental exposure; it is not encryption or a complete
  defense against inference by users who can issue arbitrary queries.

Microsoft documents regex-based masking as an Azure SQL Database preview.
Verify it in this exact container and the selected Hyperscale database before
committing the application design to it.

### 2. Native JSON: shared capability

Keep stable fields such as case ID, customer ID, status, and timestamps relational.
Use a native JSON column for variable details such as product, device, channel,
and troubleshooting context.

Demonstrate a SQL-side JSON filter as well as a readable details panel. Merely
storing an opaque JSON string would undersell the feature.

### 3. Vector search: shared capability

Embed approximately 1,000 case descriptions and resolutions. Verify a current
DiskANN vector index and `VECTOR_SEARCH` with `SELECT TOP (...) WITH APPROXIMATE`,
including iterative filtering and automatic index maintenance after DML. Keep
exact vector similarity search as the correctness/recall reference. Index
creation and successful results alone do not prove ANN execution: inspect the
execution plan, using the documented `FORCE_ANN_ONLY` hint for capability tests
when the optimizer prefers exact search on a small corpus.

Also verify a native JSON index and confirm an application-shaped JSON predicate
uses it. These local engine checks do not replace Hyperscale verification or
semantic-relevance testing with actual model-generated embeddings.

Keep embedding input free of customer contact information. Display the matched
case, resolution, and similarity/distance explanation rather than raw vectors.
Do not present a distance as a calibrated confidence percentage.

### 4. Automatic index compaction: optional supporting beat

This is another capability beyond SQL Server 2025. Enable and verify it locally
and in Azure if supported by the preview container.

Compaction is asynchronous, and 1,000 searchable cases do not guarantee a
meaningful maintenance demonstration. Keep it optional. If included, use a
separate measured workload and report actual page counts, page density, and
compaction evidence. Do not inflate the main case corpus just to force this beat.

## Data and embedding preparation

### Proposed data

- Approximately 1,000 searchable support cases, including varied JSON attributes.
- A small related set of synthetic customers with maskable contact fields.
- A handful of prepared search phrases with meaningful expected matches.
- Embedding metadata: provider, exact model/version, dimension, input-text hash,
  and preparation timestamp.

Keep the relational case content identical between local and Azure environments.
The vectors are intentionally regenerated when changing embedding models.

### Two embedding profiles

| Setting | Local profile | Azure profile |
| --- | --- | --- |
| Database | Azure SQL development container | Azure SQL Database Hyperscale serverless |
| Embedding provider | Local Ollama | Microsoft Foundry embedding deployment |
| Corpus | Same approximately 1,000 cases | Same approximately 1,000 cases |
| Document vectors | Generated ahead of time with the Ollama model | Regenerated ahead of time with the Foundry model |
| Prepared query vectors | Generated with the same local model | Generated with the same Foundry model |
| Search execution | Live SQL query | Same live SQL search logic |

There is no need to minimize vectors artificially. Select a modest model/output
dimension supported by both profiles if practical, and verify that support
before choosing the vector column definition.

Prefer a common dimension so the schema and search procedure remain unchanged.
If the selected models require different dimensions, explicitly document the
embedding-column deployment change rather than claiming the entire schema is
identical. Equal dimensions do not make different models' vectors interchangeable.

The preparation utility should select providers through configuration from the
outset. During the demonstration, the web app can use stored query embeddings
for explicitly labeled prepared searches. Do not imply those searches invoke
Ollama or Foundry live, and do not silently substitute a prepared vector for
arbitrary free-text input.

Search rankings may differ between models; identical results are not an
acceptance requirement. Valid, relevant results in each profile are.

## Local-to-Azure flow

1. **Verify the engine features.** Start the container with persistent storage
   and confirm regex masking, native JSON, and vector search actually work.
2. **Prepare the local experience.** Deploy schema and synthetic data; generate
   Ollama corpus and prepared-query embeddings.
3. **Run locally.** Show JSON filtering, masked customer details, semantic
   retrieval, and a newly created recognizable case.
4. **Copy the database to Hyperscale serverless.** Use a tested schema-and-data
   transfer route. SqlPackage BACPAC is a candidate, not an assumed working path
   for the preview types and masking definitions. Do not assume backup/restore.
5. **Prove database portability first.** Point the same local application
   artifact at Azure using the copied local embedding profile. Check the
   recognizable case and repeat the feature interactions.
6. **Change embedding providers.** Prepare Foundry document/query vectors,
   validate the replacement set completely, and switch the active profile.
   This work may happen before the presentation rather than live.
7. **Deploy the same application artifact to App Service.** Supply the Azure
   connection/authentication and active profile through configuration.
8. **Repeat the experience at the Azure URL.** Show the same data, SQL-enforced
   masks, JSON behavior, and meaningful search results.

No business-logic or query rewrite should occur during these steps.
Provider configuration, regenerated embedding data, identity grants, and
database feature settings are explicit environment/setup work.

## Authentication and configuration

- The registry pull credentials are separate from SQL and model credentials.
  Keep the existing local credentials file ignored; do not copy it into app
  publishing output or use it as application configuration.
- Store local SQL secrets in .NET user secrets or another excluded local store.
  Do not assume the preview container supports every Azure authentication mode.
- Use a developer Entra identity for local-to-Azure testing and a least-privilege
  App Service managed identity for the deployed app.
- Provision the database users and permissions separately from app startup.
  The normal application identity must not be a database owner.
- Keep Foundry generation credentials in the preparation workflow when no live
  embedding generation is needed by the web app.
- Configure SQL TLS appropriately for each environment; local certificate
  exceptions must not carry into Azure.
- Plan App Service-to-SQL network access and test it before the presentation.
  Prefer the simplest approved network arrangement, not a separate networking demo.
- Use bounded handling for transient connection failures and surface failures
  explicitly. A missing model profile or incomplete embedding set must not
  produce an apparently successful empty search.

## What stays the same and what changes

| Stays the same | Intentionally changes |
| --- | --- |
| Published web application artifact and build ID | Host URL and hosting configuration |
| UI, business behavior, and parameterized query logic | SQL endpoint and authentication configuration |
| Customer/case content and JSON semantics | Environment-specific users, grants, and feature enablement |
| Database-side masking rules and restricted-user behavior | Embedding provider/model profile |
| Search contract and result rendering | Corpus/query vectors and potentially ranking |

Keep serverless sizing and any pause/resume behavior separate from the core
portability claim. They are not required to prove the app moved successfully.

## Acceptance criteria

- Regex masking is proven to work in the container and Hyperscale and is
  confirmed as a capability beyond SQL Server 2025.
- The restricted app identity receives masked values directly from SQL in both
  environments; privileged comparisons are controlled separately.
- Native JSON filtering and live vector retrieval work against the same
  approximately 1,000 case records in both environments.
- Ollama and Foundry preparation produce complete, model-matched document/query
  vector sets with recorded dimensions and provenance.
- Schema/data transfer preserves case IDs, content, JSON, masking definitions,
  and the recognizable case created locally. Verify settings and grants separately.
- The same published app build runs locally and on App Service, with no
  environment-specific source edits.
- The local app can reach Hyperscale before application hosting changes.
- Preparation and deployment steps are repeatable, and failures are visible.
- No credentials, real customer information, or secrets appear in Git, logs,
  browser diagnostics, or the published artifact.

## Implementation order

1. Prove the three required engine features and a tiny database transfer.
2. Confirm model availability, common dimensions, runtime, and authentication.
3. Build the Razor Pages vertical slice and seed approximately 1,000 cases.
4. Prepare Ollama embeddings and validate local feature behavior.
5. Verify the Hyperscale copy and unchanged local app.
6. Prepare Foundry vectors and validate the provider transition.
7. Publish the exact tested app artifact to App Service and rehearse the flow.
8. Add an index-compaction beat only if measured behavior earns its place.

## References

- [What's new in Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/doc-changes-updates-release-notes-whats-new)
- [Regex-based dynamic data masking](https://learn.microsoft.com/azure/azure-sql/database/dynamic-data-masking-regex)
- [Automatic index compaction](https://learn.microsoft.com/sql/relational-databases/indexes/automatic-index-compaction)
- [Import a BACPAC into Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/database-import)
- [Configure ASP.NET Core on App Service](https://learn.microsoft.com/azure/app-service/configure-language-dotnetcore)
- [Connect App Service to Azure SQL with managed identity](https://learn.microsoft.com/azure/app-service/tutorial-connect-msi-sql-database)
