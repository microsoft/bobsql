# Provisions the Foundry triage agent and lets the function app call it.
#
# The agent is a real Azure resource, not a prompt buried in the function: it is
# versioned, it has its own Entra identity, and its endpoint routes traffic to
# @latest. Re-running this script publishes a new version rather than replacing
# one, so the demo can be re-provisioned mid-conference without losing history.

[CmdletBinding()]
param(
    [string]$Model = $null
)

. (Join-Path $PSScriptRoot '00-config.ps1')

if ($Model) { $script:ChatModel = $Model }

Write-Beat 'Foundry triage agent'

# --- Instructions ------------------------------------------------------------
# Kept here rather than in the function so the prompt ships with the agent
# version. Changing it is a deployment, not a code push.
$instructions = @'
You are the triage agent for a software support desk. You receive one newly
created support ticket and you take exactly one action on it, then report what
you did as though it is already done.

Choose the action from this list and nothing else:
  escalate  - notify the on-call engineer and open an incident
  assign    - route to a named internal team
  resolve   - fix or answer it now and notify the customer
  info      - the ticket lacks the detail needed to act
  monitor   - real but not yet actionable, watch it
  schedule  - plan future work such as maintenance or a feature

Reply with JSON only, in this shape:
{"action":"escalate","taken":"Opened a Sev 1 incident and notified the Payments on-call engineer","severity":1}

"taken" is one past-tense sentence, under 90 characters, written the way a
support engineer would log it. Name a team, queue, or artifact when it fits.
On-call is a person, not a system: notify an engineer or a team that owns the
service, never the service itself. Do not use the word "paged".
"severity" is your own 1-4 assessment, which may differ from the reported one.
'@

# --- Project -----------------------------------------------------------------
# ARM reports a missing identity block on the project as an account-level error,
# which is misleading. az resource create omits identity, so PUT the body here.
Write-Step "Ensuring project '$AiProject'"

$projectId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" +
             "/providers/Microsoft.CognitiveServices/accounts/$AiAccount/projects/$AiProject"
$projectUrl = "https://management.azure.com$projectId" + '?api-version=2026-07-01'
$projectBody = @{
    location   = $Location
    identity   = @{ type = 'SystemAssigned' }
    properties = @{}
} | ConvertTo-Json -Compress -Depth 5

$bodyFile = Join-Path ([System.IO.Path]::GetTempPath()) 'foundry-project.json'
Set-Content -Path $bodyFile -Value $projectBody -Encoding utf8

$project = Invoke-Az @('rest', '--method', 'put', '--url', $projectUrl, '--body', "@$bodyFile")
Remove-Item $bodyFile -ErrorAction SilentlyContinue

Write-Ok "$AiProject is $($project.properties.provisioningState)"
Write-Ok $project.properties.endpoints.'AI Foundry API'

# --- Agent -------------------------------------------------------------------
Write-Step "Publishing agent '$AgentName' on $ChatModel"

$token = (az account get-access-token --resource $AiScope --query accessToken -o tsv)
if ($LASTEXITCODE -ne 0) { Write-Fail 'Could not get a Foundry token.'; exit 1 }
$headers = @{ Authorization = "Bearer $($token.Trim())" }

$definition = @{ kind = 'prompt'; model = $ChatModel; instructions = $instructions }

$existing = $null
try {
    $existing = Invoke-RestMethod -Uri "$AiEndpoint/agents/$AgentName`?api-version=$AgentApiVersion" -Headers $headers
} catch {
    $existing = $null
}

if ($existing) {
    # A new version keeps the endpoint and identity stable; @latest picks it up.
    $body = @{ definition = $definition } | ConvertTo-Json -Compress -Depth 5
    $uri = "$AiEndpoint/agents/$AgentName/versions`?api-version=$AgentApiVersion"
} else {
    $body = @{ name = $AgentName; definition = $definition } | ConvertTo-Json -Compress -Depth 5
    $uri = "$AiEndpoint/agents`?api-version=$AgentApiVersion"
}

try {
    $agent = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -ContentType 'application/json' -Body $body
} catch {
    Write-Fail 'Agent publish failed.'
    Write-Host ($_.ErrorDetails.Message ?? $_.Exception.Message)
    exit 1
}

$version = if ($agent.id -match ':') { $agent.id } else { $agent.versions.latest.id }
Write-Ok "Published $version"

# --- Let the function app call it -------------------------------------------
Write-Step 'Granting the function app access to the agent'

$principalId = Invoke-Az @('functionapp', 'identity', 'show',
    '-n', $FunctionApp, '-g', $ResourceGroup, '--query', 'principalId')

if (-not $principalId) { Write-Fail "$FunctionApp has no system-assigned identity."; exit 1 }

$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" +
         "/providers/Microsoft.CognitiveServices/accounts/$AiAccount"

$null = Invoke-Az @('role', 'assignment', 'create',
    '--assignee-object-id', $principalId,
    '--assignee-principal-type', 'ServicePrincipal',
    '--role', $FoundryUserRole,
    '--scope', $scope) -AllowFailure

$roles = Invoke-Az @('role', 'assignment', 'list',
    '--scope', $scope, '--assignee', $principalId, '--query', '[].roleDefinitionName')

if ($roles -contains 'Foundry User') {
    Write-Ok "$FunctionApp holds Foundry User on $AiAccount"
} else {
    Write-Fail "$FunctionApp is missing Foundry User. Found: $($roles -join ', ')"
    exit 1
}

# --- App settings ------------------------------------------------------------
Write-Step 'Publishing agent settings to the function app'

$null = Invoke-Az @('functionapp', 'config', 'appsettings', 'set',
    '-n', $FunctionApp, '-g', $ResourceGroup, '--settings',
    "AgentEndpoint=$AiEndpoint",
    "AgentName=$AgentName",
    "AgentApiVersion=$AgentApiVersion")

Write-Ok "AgentEndpoint = $AiEndpoint"
Write-Ok "AgentName     = $AgentName"

Write-Step 'Done'
Write-Skip 'Deploy the function (04-function.ps1) so TicketTriage picks these up.'
