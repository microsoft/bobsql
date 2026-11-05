<#
.SYNOPSIS
    Deploys the AZURE side of AI-Ready SQL: the Microsoft Foundry account, the two
    model deployments, the SQL server's managed identity and its role
    assignment, and -- unless you pass -NoGateway -- the APIM AI gateway with
    content safety in front of the chat model.

.DESCRIPTION
    This script stops at the edge of the database. It creates the Azure
    resources the in-engine T-SQL needs to already exist, and then hands you the
    SQL scripts to run yourself.

    That hand-off is deliberate, and it is the same contract Getting Started uses.
    There, the schema DDL is the lesson, so the reader runs 01 through 05 in the
    tool of their choice. Here, the T-SQL IS the area -- the external model,
    the vector column, the DiskANN index, the procedure that calls a model and
    logs what came back. Automating it away would automate away the subject.

    So this script does the part that is plumbing. You do the part that is the
    point.

    WHAT IT CREATES
        Foundry (Azure OpenAI) account
        gpt-5 deployment                     the chat model 08 calls
        text-embedding-3-large deployment    the embedding model 06 registers
        System-assigned managed identity on the logical server
        Cognitive Services OpenAI User role for that identity
        APIM StandardV2 + content safety     unless -NoGateway

    WHAT IT DOES NOT DO
        It does not create the resource group, the logical server, or the
        wardgeneral database. Those are Getting Started and are SHARED across every
        area -- see the deploy-hyperscale skill.

        It does not run 06, 07, 08 or 09. You do, in order, after this
        finishes. The closing banner lists them.

        It does not build or run the application. That is run-ai-app.ps1.

    TIME AND COST. A first APIM StandardV2 provision takes ~30-45 minutes and
    is billable. Re-runs skip it. -NoGateway avoids it entirely, and the AI
    assistance procedure still works without it -- change @UseGateway's default
    to 0 in 08 and it calls the gpt-5 deployment directly. The gateway is
    AI-Ready SQL's governance beat, not a prerequisite for the AI story.

    IDEMPOTENT. Every underlying step is "create if absent", so a re-run after a
    failure picks up rather than starting over.

    All data is synthetic. No real PHI.

.PARAMETER SqlServerName
    Short name of the logical server (not the FQDN) whose managed identity gets
    the role assignment. Defaults to $env:SRV.

.PARAMETER ResourceGroup
    Resource group holding the server. Defaults to $env:RG. No built-in default.

.PARAMETER AiResourceName
    Name for the Microsoft Foundry (Azure OpenAI) account. It becomes
    <name>.openai.azure.com, so it must be globally unique. This is the value
    you substitute for <your-foundry> in 06 and 08. Defaults to
    $env:AI_RESOURCE.

.PARAMETER PublisherEmail
    Publisher contact for APIM -- it receives service notifications and appears
    on the developer portal. Required unless -NoGateway. Defaults to
    $env:PUBLISHER_EMAIL.

.PARAMETER SubscriptionId
    Optional. Defaults to $env:SUBSCRIPTION_ID, then whatever `az` is set to.

.PARAMETER CsResourceName
    Name of the Content Safety resource. Defaults to
    <AiResourceName>-contentsafety. Pass this if yours is named anything else:
    the name is how the script decides whether one already exists, so a mismatch
    makes it create a SECOND resource next to the one you have and re-point the
    gateway policy at it. Defaults to $env:CS_RESOURCE.

.PARAMETER NoGateway
    Skip APIM and content safety. Foundry, the models, the identity and the RBAC
    are still created.

.PARAMETER NoContentSafety
    Provision the gateway but leave content safety alone. Ignored with
    -NoGateway, which already skips both.

.PARAMETER Force
    Delete and recreate the APIM instance. This costs the full ~30-45 min
    provision again, so it is not the first thing to reach for.

.EXAMPLE
    .\deploy-ai.ps1 -SqlServerName mysqlserver -ResourceGroup rg-mine ``
        -AiResourceName my-foundry -PublisherEmail me@example.com
    Foundry, both models, RBAC, APIM and content safety.

.EXAMPLE
    .\deploy-ai.ps1 -SqlServerName mysqlserver -ResourceGroup rg-mine ``
        -AiResourceName my-foundry -PublisherEmail me@example.com ``
        -CsResourceName my-contentsafety
    Same, but against an existing Content Safety resource whose name does not
    follow the <AiResourceName>-contentsafety default. Creates nothing.

.EXAMPLE
    .\deploy-ai.ps1 -SqlServerName mysqlserver -ResourceGroup rg-mine ``
        -AiResourceName my-foundry -NoGateway
    Foundry, both models and RBAC only. No APIM, no content safety, no wait.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $SqlServerName  = ($env:SRV ?? ''),
    [string] $ResourceGroup  = ($env:RG ?? ''),
    [string] $AiResourceName = ($env:AI_RESOURCE ?? ''),
    [string] $SubscriptionId = ($env:SUBSCRIPTION_ID ?? ''),
    # APIM requires a publisher contact. Needed unless -NoGateway.
    [string] $PublisherEmail = ($env:PUBLISHER_EMAIL ?? ''),
    # Name an EXISTING Content Safety resource whose name is not the default
    # <AiResourceName>-contentsafety, or a new one would be created alongside it.
    [string] $CsResourceName = ($env:CS_RESOURCE ?? ''),
    [switch] $NoGateway,
    [switch] $NoContentSafety,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

if (-not $SqlServerName) {
    throw 'SqlServerName is required -- pass -SqlServerName <short name of your logical server>, or set the SRV environment variable. It is the server whose managed identity gets the Cognitive Services OpenAI User role.'
}
if (-not $ResourceGroup) {
    throw 'ResourceGroup is required -- pass -ResourceGroup <your resource group>, or set the RG environment variable. There is no default: a default resource group is always someone else''s.'
}
if (-not $AiResourceName) {
    throw 'AiResourceName is required -- pass -AiResourceName <globally unique Foundry name>, or set the AI_RESOURCE environment variable. It becomes <name>.openai.azure.com, so it must be unique across Azure.'
}
if (-not $NoGateway -and -not $PublisherEmail) {
    throw 'PublisherEmail is required unless -NoGateway -- pass -PublisherEmail <you@example.com>, or set the PUBLISHER_EMAIL environment variable. APIM uses it for service notifications.'
}

$started = Get-Date

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' AI-Ready SQL : Azure AI resources'               -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host "  resource group : $ResourceGroup" -ForegroundColor Gray
Write-Host "  foundry        : $AiResourceName" -ForegroundColor Gray
Write-Host "  sql server     : $SqlServerName" -ForegroundColor Gray
Write-Host "  gateway        : $(if ($NoGateway) { 'no -- the proc calls the gpt-5 deployment directly' } else { 'yes -- APIM + content safety' })" -ForegroundColor Gray
Write-Host "  content safety : $(if ($NoGateway -or $NoContentSafety) { 'skipped' } elseif ($CsResourceName) { $CsResourceName } else { "$AiResourceName-contentsafety (default)" })" -ForegroundColor Gray

# No APIM time-and-cost warning here, deliberately. By the time this script is
# running the decision is already made, so a warning at this point is too late to
# act on and only competes with the banner above. check-ai-env.ps1 is where that
# caution lives: it reports the gateway as WILL BE CREATED and says what the
# provision costs in time and money, before anyone commits to a deploy. One
# warning, in the one place a reader can still change their mind.

$azureArgs = @{
    ResourceGroup  = $ResourceGroup
    SqlServerName  = $SqlServerName
    AiResourceName = $AiResourceName
}
if ($SubscriptionId) { $azureArgs['SubscriptionId'] = $SubscriptionId }
if ($CsResourceName) { $azureArgs['CsResourceName'] = $CsResourceName }
if ($NoGateway) {
    # azureaideploy.ps1 uses the same opt-out shape, so this switch just passes
    # straight through: gateway and content safety are on unless you say no.
    $azureArgs['NoGateway'] = $true
} else {
    $azureArgs['PublisherEmail'] = $PublisherEmail
    if ($NoContentSafety) { $azureArgs['NoContentSafety'] = $true }
}
if ($Force) { $azureArgs['Force'] = $true }

# azureaideploy.ps1 throws on failure -- it checks $LASTEXITCODE after its own
# children and re-throws, and ErrorActionPreference is Stop on both sides. Do
# NOT check $LASTEXITCODE here: after a SUCCESSFUL run it still holds whatever
# the last `az` call left behind, and an existence probe that correctly returns
# 1 for "not found" is routine in that script. Checking it would fail a good run.
& (Join-Path $here 'azureaideploy.ps1') @azureArgs

$elapsed = (Get-Date) - $started

Write-Host ''
Write-Host '=============================================' -ForegroundColor Green
Write-Host ' Azure AI resources ready.'                    -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Green
Write-Host ("  elapsed  {0:hh\:mm\:ss}" -f $elapsed) -ForegroundColor Gray
Write-Host ''
Write-Host ' Now run the SQL yourself -- this is the area.' -ForegroundColor Cyan
Write-Host ''
Write-Host '   0. Replace the placeholders in 06 and 08:' -ForegroundColor White
Write-Host '        <your-foundry>  ->  your Foundry resource name' -ForegroundColor Gray
if (-not $NoGateway) {
    Write-Host '        <your-apim>     ->  your API Management service name (08)' -ForegroundColor Gray
}
Write-Host '      Each file opens with a BEFORE YOU RUN block that says which.' -ForegroundColor Gray
if ($NoGateway) {
    Write-Host ''
    Write-Host '      You deployed WITHOUT the gateway, so also change @UseGateway''s default' -ForegroundColor Yellow
    Write-Host '      in 08 from 1 to 0. The script says exactly where. Without that edit the' -ForegroundColor Yellow
    Write-Host '      proc calls an APIM instance you do not have.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '   1. 06-ai-embeddings.sql           external model, vector table, the embeddings' -ForegroundColor White
Write-Host '   2. 07-vector-index.sql            the DiskANN vector index over those vectors' -ForegroundColor White
if ($NoGateway) {
    Write-Host '   3. 08-ai-assistance.sql           the assistance proc and its append-only ledger' -ForegroundColor White
} else {
    Write-Host '   3. 08-ai-assistance.sql           the assistance proc, routed through the gateway,' -ForegroundColor White
    Write-Host '                                    and its append-only ledger' -ForegroundColor Gray
}
Write-Host '   4. 09-research-vector-search.sql  the retrieval-only proc the named replica runs' -ForegroundColor White
Write-Host ''
Write-Host '      In the MSSQL extension, SSMS, Azure Data Studio or sqlcmd -- your' -ForegroundColor Gray
Write-Host '      choice. Run them in that order: everything after 06 reads what 06 creates.' -ForegroundColor Gray
Write-Host ''
Write-Host '      06 embeds the corpus, which takes ~3-3.5 hr for the full ~60k notes --' -ForegroundColor Gray
Write-Host '      longer than an Entra token lives, so the connection WILL drop part-way.' -ForegroundColor Gray
Write-Host '      That is expected. Reconnect and run its INSERT again; it resumes. Check' -ForegroundColor Gray
Write-Host '      progress with verify-embeddings.sql and stop when MISSING=0.' -ForegroundColor Gray
if ($NoGateway) {
    Write-Host ''
    Write-Host '      Changed your mind about the gateway later? Re-run this script without' -ForegroundColor Gray
    Write-Host '      -NoGateway, put @UseGateway''s default in 08 back to 1, and re-run 08.' -ForegroundColor Gray
    Write-Host '      It is CREATE OR ALTER, so nothing is lost.' -ForegroundColor Gray
}
Write-Host ''
Write-Host ' Then put it on screen:' -ForegroundColor Cyan
Write-Host '   ./run-ai-app.ps1 -Server <your-server>.database.windows.net -Database wardgeneral' -ForegroundColor White
Write-Host ''
Write-Host ' See README.md in this folder for the full run order and the re-run notes.' -ForegroundColor DarkGray
Write-Host ''
