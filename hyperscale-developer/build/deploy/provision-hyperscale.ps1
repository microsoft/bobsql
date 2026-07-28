# =============================================================================
# Ward General Hospital — Hyperscale developer demo (provisioning)
# provision-hyperscale.ps1
#
# Create the Collier Health logical server and deploy the Ward General
# Hyperscale database under it. A single `az sql db create` deploys the
# database itself; the rest is plumbing (resource group, server, firewall,
# Entra admin). Driven by the deploy-wardgeneral-db skill.
#
# PowerShell for every script, `az` CLI for Azure control-plane calls.
# Run in PowerShell 7+ (pwsh).
#
# Prereqs:
#   * PowerShell 7+ (`$PSVersionTable.PSVersion`)
#   * Azure CLI 2.60+ (`az version`)
#   * Logged in (`az login` and `az account set -s <subscription>`)
#   * Microsoft Entra object ID + display name for the user/group that will be
#     the Entra admin. We enable MIXED auth here (SQL + Entra).
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Make native-command (az) non-zero exit codes throw, so a failed control-plane
# call stops the deploy instead of silently continuing.
$PSNativeCommandUseErrorActionPreference = $true

# ---------- Variables --------------------------------------------------------
# Resource naming convention:
#   enterprise-shared  -> `collier`
#   per-hospital       -> `ward`
# Inputs come from environment variables (the deploy-wardgeneral-db skill sets these
# live in the session); each falls back to a sensible default.
$Loc = $env:LOC ?? 'eastus2'                       # region; pick one with ZRS backup
$Rg  = $env:RG  ?? 'rg-collierhealth'
$Srv = $env:SRV ?? "collierhealth-$(Get-Random)"   # logical server: globally unique
$Db  = $env:DB  ?? 'wardgeneral'                    # the Hyperscale database

# Entra admin for the server. Replace with your tenant's values.
$AdminDisplayName = $env:ADMIN_DISPLAY_NAME ?? 'Collier Health DBAs'
if (-not $env:ADMIN_OBJECT_ID) { throw 'Set ADMIN_OBJECT_ID to the Entra group / user object id.' }
$AdminObjectId = $env:ADMIN_OBJECT_ID
$AdminType     = $env:ADMIN_TYPE ?? 'Group'         # User | Group | ServicePrincipal

# SQL admin login (mixed auth). Set
# SQL_ADMIN_PASSWORD in the environment; never hard-code it here.
$SqlAdminUser = $env:SQL_ADMIN_USER ?? 'wardadmin'
if (-not $env:SQL_ADMIN_PASSWORD) { throw 'Set SQL_ADMIN_PASSWORD for the mixed-auth SQL admin.' }
$SqlAdminPassword = $env:SQL_ADMIN_PASSWORD

# Hyperscale shape: provisioned, single database, one HA replica, zone
# redundant. (Serverless and elastic pool are other options, not used here.)
$Slo         = $env:SLO         ?? 'HS_Gen5_8'      # 8 vCore Gen5 primary; changeable later
$HaReplicas  = $env:HA_REPLICAS ?? '1'              # required for zone redundancy

# ---- Create-time-only (IMMUTABLE): these MUST be decided at deploy. There is
#      no `az sql db update` for any of them; changing later means a new DB. ----
$ZoneRedundant    = $env:ZONE_REDUNDANT    ?? 'true'    # FIXED at create; cannot toggle later
$BackupRedundancy = $env:BACKUP_REDUNDANCY ?? 'GeoZone' # FIXED at create (Local|Zone|Geo|GeoZone)
$Collation        = $env:COLLATION         ?? 'SQL_Latin1_General_CP1_CI_AS'  # FIXED; data collation
$CatalogCollation = $env:CATALOG_COLLATION ?? 'SQL_Latin1_General_CP1_CI_AS'  # FIXED; metadata/catalog collation
$Ledger           = $env:LEDGER            ?? 'false'   # FIXED; true => ledger database (all tables ledger)
$AvailabilityZone = $env:AVAILABILITY_ZONE ?? ''        # FIXED; pin primary to AZ 1|2|3 — only when NOT zone-redundant

# ---- Changeable after deploy (parameterized for completeness; each has an
#      `az sql ... update` path). Safe defaults let the base deploy ignore them. ----
$AllowAzureServices     = $env:ALLOW_AZURE_SERVICES     ?? 'true'   # dev/test convenience; disable for prod
$AssignIdentity         = $env:ASSIGN_IDENTITY          ?? 'true'   # server managed identity: keyless auth to Azure OpenAI/Foundry & Key Vault for TDE CMK
$IdentityType           = $env:IDENTITY_TYPE            ?? 'SystemAssigned'  # None|SystemAssigned|UserAssigned|'SystemAssigned,UserAssigned'
$UserAssignedIdentityId = $env:USER_ASSIGNED_IDENTITY_ID ?? ''      # resource id of a user-assigned identity
$PrimaryUamiId          = $env:PRIMARY_UAMI_ID         ?? ''        # primary user-assigned identity resource id
$MinimalTlsVersion      = $env:MINIMAL_TLS_VERSION     ?? '1.2'     # inbound TLS floor: 1.0|1.1|1.2|1.3
$EnablePublicNetwork    = $env:ENABLE_PUBLIC_NETWORK   ?? 'true'    # false => reachable only via Private Link
$MaintConfigId          = $env:MAINT_CONFIG_ID         ?? ''        # maintenance window config id/name; empty => system default
$BackupRetentionDays    = $env:BACKUP_RETENTION_DAYS   ?? '7'       # PITR short-term retention 1-35 days; applied post-create

# Resource tags (governance / ownership / lifecycle) applied to the RG, server,
# and database. Follows the Cloud Adoption Framework tagging categories
# (functional / classification / accounting / ownership). Override the whole
# set with $env:TAGS as space-separated key=value pairs.
if ($env:TAGS) {
    $Tags = $env:TAGS -split '\s+' | Where-Object { $_ }
} else {
    $ownerTag = if ($AdminDisplayName) { ($AdminDisplayName -replace '\s+', '-') } else { 'collier-health-dba' }
    # A follow-along TEST database. Tags state what the resource IS now
    # (a sandbox with synthetic data).
    $Tags = @(
        'environment=sandbox',             # functional: sandbox | dev | test | prod
        'application=ward-general-ehr',    # functional: the workload this DB serves
        "owner=$ownerTag",                 # ownership: team/principal accountable
        'criticality=low',                 # classification: a sandbox, not a live EHR
        'dataClassification=nonproduction' # classification: synthetic / no-PHI seed
    )
}

Write-Host "Region:      $Loc"
Write-Host "RG:          $Rg"
Write-Host "Server:      $Srv"
Write-Host "Database:    $Db"
Write-Host "Service tier: $Slo  (HA=$HaReplicas, ZR=$ZoneRedundant)"
Write-Host "Backup:      $BackupRedundancy  (PITR retention: $BackupRetentionDays days)"
Write-Host "Collation:   $Collation  (catalog: $CatalogCollation, ledger: $Ledger)"
Write-Host "Identity:    assign=$AssignIdentity type=$IdentityType  |  TLS>=$MinimalTlsVersion  |  PublicNet=$EnablePublicNetwork"
Write-Host "Tags:        $($Tags -join ' ')"
Write-Host ""

# ---------- Capacity check (preamble) ----------------------------------------
# Before we burn time on `az group create`, make sure Hyperscale + the chosen
# shape are actually available in this region for this subscription.
Write-Host "--- Capacity check: Hyperscale availability in $Loc ---"
az sql db list-editions `
    --location $Loc `
    --edition Hyperscale `
    --service-objective $Slo `
    --available `
    -o table

# ---------- 1. Resource group ------------------------------------------------
Write-Host ""
Write-Host "--- 1/4 Resource group: $Rg ---"
az group create --name $Rg --location $Loc --tags @Tags -o table

# ---------- 2. Logical server (mixed auth: SQL + Entra) ----------------------
# Mixed auth keeps a familiar SQL login alongside an Entra admin. (Entra-only
# is a hardening step you can flip later with --enable-ad-only-auth true.)
# Keep the SQL password in the environment.
#
# The server managed identity is how SQL authenticates WITHOUT keys to Azure
# OpenAI / Foundry and to Key Vault for TDE customer-managed keys.
# Changeable later via `az sql server update`.
Write-Host ""
Write-Host "--- 2/4 Logical server: $Srv (mixed SQL + Entra auth) ---"
$serverIdentityArgs = @()
if ($AssignIdentity -eq 'true') {
    $serverIdentityArgs += @('--assign-identity', '--identity-type', $IdentityType)
    if ($UserAssignedIdentityId) { $serverIdentityArgs += @('--user-assigned-identity-id', $UserAssignedIdentityId) }
    if ($PrimaryUamiId)          { $serverIdentityArgs += @('--primary-user-assigned-identity-id', $PrimaryUamiId) }
}
az sql server create `
    --name $Srv `
    --resource-group $Rg `
    --location $Loc `
    --admin-user $SqlAdminUser `
    --admin-password $SqlAdminPassword `
    --external-admin-principal-type $AdminType `
    --external-admin-name $AdminDisplayName `
    --external-admin-sid $AdminObjectId `
    --minimal-tls-version $MinimalTlsVersion `
    --enable-public-network $EnablePublicNetwork `
    --tags @Tags `
    @serverIdentityArgs `
    -o table

# ---------- 3. Firewall: allow Azure services + this client IP ---------------
# "Allow Azure services" (0.0.0.0) is convenient in dev/test so downstream
# Azure services (Foundry, MCP servers, Functions) can reach the server. It is
# broad exposure — disable for production. Gated on ALLOW_AZURE_SERVICES.
Write-Host ""
Write-Host "--- 3/4 Firewall rules ---"
if ($AllowAzureServices -eq 'true') {
    az sql server firewall-rule create `
        --resource-group $Rg `
        --server $Srv `
        --name AllowAllAzureIps `
        --start-ip-address 0.0.0.0 `
        --end-ip-address 0.0.0.0 `
        -o table
} else {
    Write-Host "Skipping 'Allow Azure services' rule (ALLOW_AZURE_SERVICES=$AllowAzureServices)."
}

$MyIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
Write-Host "Client IP: $MyIp"
az sql server firewall-rule create `
    --resource-group $Rg `
    --server $Srv `
    --name "AllowClient-$([System.Net.Dns]::GetHostName())" `
    --start-ip-address $MyIp `
    --end-ip-address $MyIp `
    -o table

# ---------- 4. The Hyperscale database — the headline command ----------------
# A single `az sql db create` deploys the Hyperscale database. The teaching
# beats this command lands:
#   * --edition Hyperscale         : the service tier
#   * --service-objective $Slo     : the vCore shape (Gen5_8 here)
#   * --ha-replicas 1              : pre-provision one HA replica
#                                     (required for ZR, and faster failover)
#   * --zone-redundant true        : commit at create time; cannot be toggled
#                                     in place on an existing database
#   * --backup-storage-redundancy  : GeoZone = ZRS-resilient backups; also a
#                                     create-time decision on Hyperscale
#   * --collation / --catalog-collation : data & metadata collation; create-only
#   * --ledger-on Disabled|Enabled : ledger database; create-only, immutable
#   * --availability-zone          : pin primary to a zone (only when NOT ZR)
Write-Host ""
Write-Host "--- 4/4 Hyperscale database: $Db ---"
# Assemble the immutable, create-time-only flags. None of these have an
# `az sql db update` equivalent — they must be set now or not at all.
$dbArgs = @('--catalog-collation', $CatalogCollation)
if ($Ledger -eq 'true') { $dbArgs += @('--ledger-on', 'Enabled') }
else                    { $dbArgs += @('--ledger-on', 'Disabled') }
# Availability-zone pinning is mutually exclusive with zone redundancy; only
# pass it when explicitly set AND the DB is not zone-redundant.
if ($AvailabilityZone) {
    if ($ZoneRedundant -eq 'true') {
        Write-Host "NOTE: AVAILABILITY_ZONE=$AvailabilityZone ignored because ZONE_REDUNDANT=true."
    } else {
        $dbArgs += @('--availability-zone', $AvailabilityZone)
    }
}
# Maintenance window (changeable later) — pass through when set.
if ($MaintConfigId) { $dbArgs += @('--maint-config-id', $MaintConfigId) }
az sql db create `
    --name $Db `
    --resource-group $Rg `
    --server $Srv `
    --edition Hyperscale `
    --service-objective $Slo `
    --ha-replicas $HaReplicas `
    --zone-redundant $ZoneRedundant `
    --backup-storage-redundancy $BackupRedundancy `
    --collation $Collation `
    --tags @Tags `
    @dbArgs `
    -o table

# ---------- 4b. Short-term (PITR) backup retention ---------------------------
# Retention is NOT a create flag; it's set on the live database and is
# changeable anytime (1-35 days). Only call out to change it from the 7-day
# default so the base deploy stays a single create.
if ($BackupRetentionDays -ne '7') {
    Write-Host ""
    Write-Host "--- PITR short-term retention -> $BackupRetentionDays days ---"
    az sql db str-policy set `
        --resource-group $Rg `
        --server $Srv `
        --name $Db `
        --retention-days $BackupRetentionDays `
        -o table
}

# ---------- Show what we got -------------------------------------------------
Write-Host ""
Write-Host "--- Database summary ---"
az sql db show `
    --name $Db `
    --resource-group $Rg `
    --server $Srv `
    --query "{name:name, edition:edition, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount, zr:zoneRedundant, state:status}" `
    -o table

@"

Done.

Next:
  1. Run ../sql/connect-and-verify.sql against $Srv.database.windows.net / $Db.
  2. Run ../sql/01-schemas.sql -> ../sql/05-seed.sql to build the schema + seed.
  3. (Optional AI layer — needs a Microsoft Foundry / Azure OpenAI resource)
     Run ../sql/06-ai-embeddings.sql then ../sql/07-ai-assistance.sql.
     Edit the Foundry endpoint + deployment placeholders at the top of 07/08
     first, and grant the database's managed identity "Cognitive Services
     OpenAI User" on the Foundry resource (passwordless).

Pricing-model reminders (the model, not numbers):
  * No SQL Server software license fee on Hyperscale.
  * Per-replica compute billing: primary + each HA replica + each named
    replica is its own meter. 1 HA = 2x compute, not 1x.
  * Storage is billed on actual allocation (10 GB minimum, 10 GB increments).
  * Backup storage is billed separately.
  * AHB is NOT available for new Hyperscale databases; existing HS single
    DBs with provisioned compute keep AHB only until December 2026
    (see Microsoft Learn — Azure SQL Hyperscale service tier).
"@ | Write-Host
# ---------- Estimated monthly cost (live) ------------------------------------
# Print a live, itemized estimate from the Azure Retail Prices API for the
# shape we just deployed. Numbers are generated at run time — the model
# matters more than the figure, which ages.
Write-Host ""
if (Test-Path "$PSScriptRoot/estimate-cost.ps1") {
    & "$PSScriptRoot/estimate-cost.ps1" -Loc $Loc -Slo $Slo -HaReplicas ([int]$HaReplicas) -BackupRedundancy $BackupRedundancy
}