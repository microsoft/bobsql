# Azure SQL Database container

Run an Azure SQL Database development environment locally, with a synthetic
Customer Service Desk application that demonstrates JSON, dynamic data masking,
and vector search. The container uses the public preview Azure SQL Database
engine, not the SQL Server container image. See the
[Azure SQL Developer Hub](https://microsoft.github.io/azure-sql-dev-hub/container/get-started.html)
for image documentation and license terms.

## What is included

- **Container scripts:** preflight, pull, start, and SQL readiness checks.
- **Customer Service Desk:** a .NET Razor Pages application with SQL-backed
  cases, masked contact information, JSON filtering, and semantic search.
- **SQL Migration Studio:** a separate, approval-gated local application for
  exploring migration to Azure SQL. See its [README](migration-studio/README.md).
- **Tests:** container lifecycle, application, and migration workflows.

The database contains synthetic data. This is a local development demo, not a
production deployment; validate behavior independently in Azure SQL Database.

## Prerequisites

- Windows, PowerShell 7.4+, and Docker Desktop using Linux x64 containers.
- Review the [public preview image terms](https://microsoft.github.io/azure-sql-dev-hub/container/get-started.html)
  before accepting the EULA.
- .NET 10 SDK and the PowerShell `SqlServer` module for the Service Desk.
- Ollama with `nomic-embed-text:v1.5` for embedding preparation and live
  semantic search.
- Microsoft Edge to open the application with the provided launcher.

Run the following commands in PowerShell from this folder. Install the embedding
model once, then check Docker and Ollama:

```powershell
ollama pull nomic-embed-text:v1.5
.\preflight.ps1
```

Preflight checks the Docker engine and generates a real local embedding; it
does not download the container image. Use `.\preflight.ps1 -DockerOnly` to
check Docker without Ollama. Add `-StartDockerDesktop` to explicitly allow the
script to start Docker Desktop if needed.

## Start the container

After reviewing the license terms:

```powershell
.\start-container.ps1 -StartDockerDesktop -AcceptEula
```

The script pulls the public image, prompts securely for a strong initial SQL
`sa` password, creates persistent storage, and waits for a successful SQL
query. The registry does not require credentials.

| Setting | Default |
| --- | --- |
| Image | `mcr.microsoft.com/mssql/azure-sql-db-server:latest` |
| Container | `sqldbcontainer` |
| Data volume | `sqldbcontainer-public-data` |
| SQL endpoint | `localhost,14332` |
| Port binding | `14332:1433` on host interfaces |

Standard Docker port publishing may allow other computers to connect if the
host firewall permits it. Use this configuration only in an appropriate demo
environment. For local client connections, use SQL authentication and trust the
self-signed server certificate.

To pull separately, resume without pulling, or stop:

```powershell
.\pull-container.ps1
.\start-container.ps1 -SkipPull
docker stop sqldbcontainer
```

Stopping does not delete the volume. A matching existing container is reused;
a mismatched container is not replaced. Pulling a newer image does not upgrade
an existing container. Plan upgrades and preserve an offline data copy before
switching images: changing engines can upgrade database files and make rollback
unsafe. This script does not automatically migrate private-preview volumes.

Use `-ContainerName`, `-VolumeName`, and `-Port` together for a separate
instance, and `-Image` to pin a public image tag or digest. The database and app
setup scripts' `-UseContainerCredentials` option is limited to the default
container and endpoint. `-SaPassword` accepts a `SecureString` for initial
creation only; it does not change an existing SQL login. When reusing a data
volume, supply its existing `sa` password.

If a matching older container has a loopback-only port binding,
`.\start-container.ps1 -SkipPull -RepairLocalhost` explicitly replaces its
container definition using the **same image build and volume**. It retains the
stopped original container for rollback and will not combine the repair with
an image upgrade. Never start both containers on the same volume.

Docker administrators can inspect container environment variables, including
the initial SQL password. Do not share full container inspection output.
The readiness probe uses the initial password in the container environment; if
`sa` is changed later, that probe must also be updated.

## Build the database and app

With the container and Ollama running:

```powershell
.\build-database.ps1 -UseContainerCredentials
.\setup-app.ps1 -UseContainerCredentials
.\build-app.ps1
.\run-app.ps1
```

Alternatively, omit `-UseContainerCredentials` to enter a SQL administrator
credential securely. The database build creates `CustomerServiceDesk`, prepares
synthetic customers, cases and six example searches, generates embeddings
locally, builds the vector index, and runs its data checks. It adds missing
seed rows without resetting existing cases; prepared example wording and stale
embeddings can be updated. No model is called from SQL Server.

Run `setup-app.ps1` with the web app stopped. It deploys the app procedures,
executes rollback-only SQL tests, and creates or rotates the restricted web
user's password. The connection is saved in the current user's .NET user secrets
store, outside the project. User secrets are a developer convenience, not an
encrypted vault.

The launcher verifies the published app and opens
**http://localhost:5187** in Edge. Use `-NoBrowser` for a server-only launch.
It prints the process ID; stop that specific process before republishing:
`Stop-Process -Id <printed-PID>`. The app listens only on localhost and has no
end-user authentication. Do not expose it publicly without adding appropriate
authentication, authorization, HTTPS, and hosting safeguards.

## Explore the demo

- Filter cases by status and contact channel. Hover or focus **Apply filters**
  to see the SQL `JSON_VALUE` predicate.
- Open a case to see SQL-masked contact details and the masking expressions.
- Search related cases using a prepared example or your own words. Exact
  prepared examples reuse stored query vectors; new text uses local Ollama.
  Both paths query the same SQL vector search procedure.
- Open **Environment** to see live engine and index metadata. A vector
  distance is not a confidence score, and index metadata does not prove a
  particular query used the index.

Changing a case's searchable text makes its embedding stale. Search reports this
explicitly; rerun `.\build-database.ps1 -UseContainerCredentials` to refresh
embeddings. Prepared searches do not require a live model call, but free-text
search does.

## Verify and troubleshoot

```powershell
.\verify-app.ps1
Invoke-Pester .\container.Tests.ps1
dotnet test .\tests\CustomerServiceDesk.Tests\CustomerServiceDesk.Tests.csproj --configuration Release
docker logs --tail 80 sqldbcontainer
```

App verification exercises SQL health, filtering, masking, prepared and live
vector searches, permissions, and rejected invalid writes. It requires the app
and Ollama to be running and does not create or edit cases. Container tests
mock Docker and Ollama; they do not prove a live image works.

For manual engine checks, run [01-create-database.sql](01-create-database.sql),
[02-verify-features.sql](02-verify-features.sql), and
[03-verify-indexes.sql](03-verify-indexes.sql) in order using the MSSQL
extension. Azure SQL requires separate connections for different databases;
follow each script's database directives. The index check uses synthetic
fixtures and requires appropriate administrator and plan-cache permissions.

The numbered SQL files, PowerShell scripts, `app`, `tests`, and
`migration-studio` are the project source. [PROPOSAL.md](PROPOSAL.md) records
the original design and may describe future work rather than current behavior.
Keep credentials and generated build output out of source control.
