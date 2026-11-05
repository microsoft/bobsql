# Deploy the Ward General application to Azure App Service

This guide moves the Ward General App application process from local Kestrel to Azure
App Service. It deploys exactly these projects:

- `WardGeneral.Web` — the ASP.NET Core Blazor Web App and App Service entry point
- `WardGeneral.Data` — the data-access library referenced by the web project
- `WardGeneral.Agent` — the agent library referenced by the web project

Only `WardGeneral.Web` is published directly. `dotnet publish` follows its project
references and places `WardGeneral.Data.dll`, `WardGeneral.Agent.dll`, and their
dependencies in the same publish directory. The result is one App Service web
app, not three App Service resources.

This guide does **not** move or recreate the `wardgeneral` Hyperscale database,
run any area SQL, deploy Data API Builder (DAB), deploy an MCP endpoint, or
create Azure OpenAI resources. Those remain external dependencies. Keep
`Features__AiAssistance` and `Features__AiAgent` off unless the corresponding
AI-Ready SQL and Agentic AI dependencies already exist and are reachable from App
Service.

> **Cost and scope.** The commands below create billable Azure resources. Review
> the App Service plan SKU and region before running them. They do not alter the
> existing Hyperscale database.

## What changes

Locally, `Microsoft.Data.SqlClient` uses `Active Directory Default` to discover
the developer's Azure CLI, Visual Studio, or VS Code identity. In App Service,
the same driver and unchanged application code discover the web app's
system-assigned managed identity. The only required application settings are the
existing SQL server and database names. There is still no database password or
connection-string secret.

```text
Browser -> Azure App Service
              WardGeneral.Web
                  |-- WardGeneral.Data.dll -> Azure SQL Hyperscale
                  `-- WardGeneral.Agent.dll -> optional Azure OpenAI and MCP services
```

App Service can reach Azure SQL in either of two ways:

- **Public SQL endpoint:** allow the App Service outbound IP addresses through
  the SQL logical-server firewall.
- **Private Link:** integrate App Service with a delegated VNet subnet and use an
  Azure SQL private endpoint in that VNet or a peered VNet. Link the
  `privatelink.database.windows.net` private DNS zone to the integration VNet.

Private Link changes the network path, not the connection string. In both cases,
keep `WardGeneral__Server` set to the normal
`<server>.database.windows.net` fully qualified name.

## Prerequisites

- The Ward General App app builds locally with the .NET 10 SDK and PowerShell 7.
- The existing `wardgeneral` database contains the Getting Started schema and seed.
- The signed-in operator can create App Service resources and enable a managed
  identity.
- A Microsoft Entra administrator is configured for the Azure SQL logical
  server. That administrator, or another sufficiently privileged Entra database
  principal, must create the managed identity's contained database user.
- Azure CLI is installed and signed in to the subscription that will host App
  Service.
- For Private Link, an Azure SQL private endpoint, its private DNS zone, and a
  VNet subnet available for App Service integration already exist. Creating
  those network resources is outside this application-migration guide.

Confirm the active account before creating anything:

```powershell
az login
az account show --query "{subscription:name, user:user.name}" -o table
```

## 1. Choose the deployment values

Run these commands from the repository root. Replace every placeholder before
continuing. The web app name must be globally unique.

```powershell
$resourceGroup = '<app-resource-group>'
$location = '<azure-region>'
$planName = '<app-service-plan-name>'
$appName = '<globally-unique-web-app-name>'
$sqlServerFqdn = '<sql-server>.database.windows.net'
$sqlDatabase = 'wardgeneral'
```

Use an App Service region close to the database unless another requirement
controls placement. Network distance between the application and database adds
latency to every database round trip.

## 2. Create App Service and its identity

The following example creates a Linux App Service plan and a .NET 10 web app.
`B1` is a starting SKU for completing the migration, not a production sizing
recommendation. Choose a plan based on the workload's measured CPU, memory,
scale, availability, and networking requirements.

```powershell
az group create `
    --name $resourceGroup `
    --location $location

az appservice plan create `
    --name $planName `
    --resource-group $resourceGroup `
    --sku B1 `
    --is-linux

az webapp create `
    --resource-group $resourceGroup `
    --plan $planName `
    --name $appName `
    --runtime 'DOTNETCORE|10.0' `
    --assign-identity
```

Verify that Azure returned a principal ID for the system-assigned identity:

```powershell
$principalId = az webapp identity show `
    --resource-group $resourceGroup `
    --name $appName `
    --query principalId `
    --output tsv

if (-not $principalId) { throw 'The App Service managed identity was not created.' }
$principalId
```

The identity's display name is normally the App Service name. Use the returned
principal ID to verify the principal rather than assuming that a similarly named
identity is the correct one.

## 3. Authorize the managed identity in `wardgeneral`

Connect to the existing database as its Microsoft Entra administrator. Create a
contained user mapped to the App Service system-assigned managed identity, then
grant only the permissions needed by the application.

```sql
CREATE USER [<app-service-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<app-service-name>];
GRANT EXECUTE ON SCHEMA::clinical TO [<app-service-name>];
```

Replace `<app-service-name>` with the exact App Service name. `db_datareader` is
needed because the Ward General App data layer reads views such as `ops.vBedCensus`
directly; `GRANT EXECUTE` covers its `clinical` stored-procedure contract. Do not
add `db_datawriter` or `db_ddladmin` for the base Ward General App application: it does
not need either role.

Later areas can add capabilities that need additional permissions. Grant
those when enabling the corresponding feature, not as part of this migration.
For example, Agentic AI owns the approval-gated write path exposed through DAB;
it is not a direct write from this App Service identity.

## 4. Configure the application

App Service settings override `appsettings.json` through ASP.NET Core's standard
double-underscore mapping. Configure the same keys used locally:

```powershell
az webapp config appsettings set `
    --resource-group $resourceGroup `
    --name $appName `
    --settings `
        WardGeneral__Server=$sqlServerFqdn `
        WardGeneral__Database=$sqlDatabase `
        ASPNETCORE_ENVIRONMENT=Production `
        Features__AiAssistance=false `
        Features__AiAgent=false
```

Do not add a SQL username, password, client secret, or access token. The existing
`WardGeneralConnectionFactory` already specifies encrypted connections,
certificate validation, and `Active Directory Default` authentication.

## 5. Choose the SQL network path

Complete **one** of the following branches.

### Option A: Public SQL endpoint

List every possible outbound IP address for the web app:

```powershell
az webapp show `
    --resource-group $resourceGroup `
    --name $appName `
    --query "{current:outboundIpAddresses,possible:possibleOutboundIpAddresses}" `
    --output json
```

Add the required addresses to the Azure SQL logical-server firewall. Use the
**possible** outbound addresses when the firewall must continue to work across
App Service infrastructure changes or scale operations. Keep public network
access enabled on the SQL logical server.

This is the shortest path, but it creates more firewall maintenance than
Private Link. The SQL connection is still encrypted and authenticated with
Microsoft Entra managed identity.

### Option B: Private Link

The App Service VNet integration subnet and private endpoint subnet serve
different purposes. Integrate the web app with the subnet reserved and delegated
for App Service; do not place the web app integration on the private endpoint
subnet.

```powershell
$vnetName = '<vnet-name>'
$integrationSubnet = '<app-service-integration-subnet>'

az webapp vnet-integration add `
    --resource-group $resourceGroup `
    --name $appName `
    --vnet $vnetName `
    --subnet $integrationSubnet
```

Confirm all of the following in Azure before disabling SQL public access:

1. The SQL private endpoint is approved and has a private IP address.
2. The private DNS zone is named `privatelink.database.windows.net`.
3. The zone is linked to the VNet used by App Service integration.
4. The SQL private endpoint has a DNS zone group associated with that zone.
5. The app still uses `<server>.database.windows.net`, not the private IP or the
   `privatelink` name.

From the App Service networking tools, resolve
`<server>.database.windows.net`. It must follow the Private Link DNS chain and
return the private endpoint IP. Test the application through the private path
before disabling public network access on the SQL logical server.

VNet integration controls **outbound** traffic from App Service to SQL. It does
not make the web application's own inbound endpoint private. Making the website
private is a separate App Service private-endpoint decision and is outside this
database-connectivity migration.

## 6. Publish the three-project application

Stop the local app before a clean publish so Windows cannot retain stale locked
assemblies:

```powershell
./first-app/shutdown.ps1
./first-app/build.ps1 -Clean -Publish -Configuration Release
```

The publish output is:

```text
first-app/src/WardGeneral.Web/publish/
```

Verify that the single output contains all three project assemblies:

```powershell
$publishPath = './first-app/src/WardGeneral.Web/publish'
Get-Item `
    "$publishPath/WardGeneral.Web.dll", `
    "$publishPath/WardGeneral.Data.dll", `
    "$publishPath/WardGeneral.Agent.dll"
```

Create the ZIP from the **contents** of the publish directory. Do not wrap the
publish directory itself in another top-level folder.

```powershell
$packagePath = Join-Path ([IO.Path]::GetTempPath()) 'wardgeneral-appservice.zip'
Compress-Archive -Path "$publishPath/*" -DestinationPath $packagePath -Force

az webapp deploy `
    --resource-group $resourceGroup `
    --name $appName `
    --src-path $packagePath `
    --type zip
```

## 7. Validate the deployed application

Read the deployed URL and open it in a normal browser:

```powershell
$appUrl = "https://$appName.azurewebsites.net"
$appUrl
Start-Process msedge.exe -ArgumentList '--new-window', $appUrl
```

Validate the behavior, not only the deployment status:

1. The unit board loads beds and patients from `wardgeneral`.
2. Opening an occupied bed loads its patient chart.
3. The target banner shows the expected database and SQL server FQDN.
4. `Features__AiAssistance` and `Features__AiAgent` remain off unless their
   external dependencies have already been deployed and configured.

If the application fails, enable and inspect the App Service log stream:

```powershell
az webapp log config `
    --resource-group $resourceGroup `
    --name $appName `
    --application-logging filesystem `
    --level information

az webapp log tail `
    --resource-group $resourceGroup `
    --name $appName
```

Use the failure boundary to choose the check:

- **Startup says `WardGeneral:Server` is missing:** verify the App Service app
  setting is named `WardGeneral__Server` with two underscores.
- **Login failed for a token-identified principal:** verify the contained user
  maps to this App Service's managed identity and exists in `wardgeneral`.
- **SQL connection timeout on the public path:** verify the SQL firewall includes
  the App Service possible outbound addresses.
- **SQL connection timeout on the private path:** verify VNet integration,
  routing, private-endpoint approval, and that DNS resolves the normal SQL FQDN
  to the private IP.
- **The base app works but the assistant fails:** the three application
  assemblies were migrated, but `WardGeneral.Agent` still needs reachable Azure
  OpenAI and DAB/MCP endpoints plus their Agentic AI configuration and identity
  permissions.

## 8. Operate and update it

For each application update, repeat only the publish, package, deploy, and
behavior-validation steps. App Service restarts the application after ZIP
deployment; the SQL managed identity and network path remain in place.

For production, add deployment slots, health checks, Application Insights,
capacity and autoscale rules, and a tested rollback procedure according to the
service requirements. Those operational controls are intentionally separate
from proving this three-project migration.

## Microsoft Learn references

Verified September 15, 2026:

- [Deploy an ASP.NET web app to Azure App Service](https://learn.microsoft.com/azure/app-service/quickstart-dotnetcore)
- [Deploy files to Azure App Service](https://learn.microsoft.com/azure/app-service/deploy-zip)
- [Connect App Service to Azure SQL with managed identity](https://learn.microsoft.com/azure/app-service/tutorial-connect-msi-sql-database)
- [Use managed identities for App Service](https://learn.microsoft.com/azure/app-service/overview-managed-identity)
- [Integrate an App Service app with an Azure virtual network](https://learn.microsoft.com/azure/app-service/overview-vnet-integration)
- [Azure Private Link for Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview?view=azuresql)
