# Shared configuration and output helpers for Demo 5 (app dev / change event streaming).
# Every other script in this folder dot-sources this file.

$ErrorActionPreference = 'Stop'

# --- Azure -------------------------------------------------------------------
$script:SubscriptionId = '0efc44aa-c965-420f-aac4-fff305dbcc97'
$script:ResourceGroup  = 'bwappdevrg'
$script:Location       = 'eastus2'

# --- Azure SQL ---------------------------------------------------------------
$script:ServerName   = 'bwappdev-srv'
$script:DatabaseName = 'bwappdev'
$script:ServerFqdn   = "$ServerName.database.windows.net"

# --- Event Hubs --------------------------------------------------------------
$script:EventHubNamespace = 'bwappdev-ehns'
$script:EventHubName      = 'ticket-events'
$script:EventHubFqdn      = "$EventHubNamespace.servicebus.windows.net"

# --- SignalR -----------------------------------------------------------------
$script:SignalRName = 'bwappdev-signalr'
$script:SignalRUri  = "https://$SignalRName.service.signalr.net"
$script:SignalRHub  = 'tickets'

# --- Function app ------------------------------------------------------------
$script:FunctionApp     = 'bwappdev-func'
$script:StorageAccount  = 'bwappdevfuncsa'
$script:FunctionRuntime = 'dotnet-isolated'
$script:FunctionVersion = '9.0'

# --- Microsoft Foundry -------------------------------------------------------
# gpt-4.1-mini won the bake-off: ~862 ms median vs ~1700 ms for the gpt-5 family,
# and it was the only fast model that still answered "need more info" instead of
# inventing a fix for a ticket with no detail in it. See bake-off-results.json.
$script:AiAccount       = 'bwappdev-ai'
$script:AiProject       = 'tickettriage'
$script:AiEndpoint      = "https://$AiAccount.services.ai.azure.com/api/projects/$AiProject"
$script:ChatModel       = 'gpt-4.1-mini'
$script:AgentName       = 'ticket-triage'
$script:AgentApiVersion = 'v1'
# Foundry data-plane tokens come from this audience, not management.azure.com.
$script:AiScope         = 'https://ai.azure.com'
# Roles were renamed, so Azure only resolves them reliably by GUID.
$script:FoundryUserRole = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
# A second consumer group lets triage read the same stream without slowing the
# card down -- the two functions race, they do not queue behind each other.
$script:TriageConsumerGroup = 'triage'

# --- CES ---------------------------------------------------------------------
$script:StreamGroupName = 'ticketStreamGroup'
$script:CredentialName  = 'ces_eventhubs_cred'
$script:TableName       = 'dbo.SupportTicket'

# --- Local -------------------------------------------------------------------
$script:WebPort      = 8080
$script:WebOrigin    = "http://localhost:$WebPort"
$script:SqlDir       = Join-Path $PSScriptRoot 'sql'
$script:SrcDir       = Join-Path $PSScriptRoot 'src'
$script:WebDir       = Join-Path $PSScriptRoot 'web'
$script:SqlSim       = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe'

# --- Output helpers ----------------------------------------------------------

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Red
}

function Write-Beat {
    param([string]$Message)
    Write-Host ''
    Write-Host ('=' * 74) -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host ('=' * 74) -ForegroundColor Cyan
    Write-Host ''
}

function Show-Command {
    param([string]$Command)
    Write-Host "    $Command" -ForegroundColor White -BackgroundColor DarkBlue
}

# --- az wrapper --------------------------------------------------------------

function Invoke-Az {
    param([string[]]$Arguments, [switch]$AllowFailure)

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "az $($Arguments -join ' ') failed with exit code $LASTEXITCODE`n$($output | Out-String)"
    }

    # 2>&1 folds stderr warnings into ErrorRecords. Keep stdout only.
    $stdout = $output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    if ([string]::IsNullOrWhiteSpace($stdout)) { return $null }

    $parsed = ($stdout | Out-String | ConvertFrom-Json)

    # `az ... show` on a missing resource can exit 0 and print '{}'. Treat a
    # property-less object as absent so callers can test for $null.
    if ($parsed -is [pscustomobject] -and @($parsed.PSObject.Properties).Count -eq 0) {
        return $null
    }
    return $parsed
}

function Add-SqlFirewallRule {
    param(
        [Parameter(Mandatory)][string]$Ip,
        [Parameter(Mandatory)][string]$RuleName
    )
    Invoke-Az @(
        'sql', 'server', 'firewall-rule', 'create',
        '-g', $script:ResourceGroup,
        '-s', $script:ServerName,
        '-n', $RuleName,
        '--start-ip-address', $Ip,
        '--end-ip-address', $Ip
    ) -AllowFailure | Out-Null
}

# Azure sees this laptop's public egress address, so open exactly that one.
#
# If a tunnelling client is active - Global Secure Access, a corporate VPN -
# traffic egresses from that vendor's edge instead, the address is not yours,
# and it can differ per connection. The verify step catches that and says so
# rather than papering over it with retries.
function Set-PresenterFirewall {
    $ip = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 20).ip
    Add-SqlFirewallRule -Ip $ip -RuleName 'presenter'
    Write-Ok "Firewall open for $ip"

    try {
        $seen = Invoke-Sql -Database 'master' -Query 'SELECT client_net_address FROM sys.dm_exec_connections WHERE session_id = @@SPID;'
    }
    catch {
        throw @"
Opened the firewall for $ip but still cannot reach $($script:ServerFqdn).

That usually means a tunnelling client is redirecting Azure-bound traffic, so
the server sees an address that is not yours. Check for Global Secure Access:
    Get-Service GlobalSecureAccess*
If its Engine / Forwarding Profile / Tunneling services are Running, stop them
or pause the client from the system tray, then run this again.

$($_.Exception.Message)
"@
    }

    if ($seen -ne $ip) { Write-Warn "Server sees $seen, not $ip - something is rewriting your egress address" }
}

# --- T-SQL helper ------------------------------------------------------------
# All DDL runs from the laptop as the Entra admin, via sqlsim with an Azure
# access token. No SQL login, no password, no connection string anywhere.

function Get-SqlAccessToken {
    $token = & az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Could not acquire an Azure SQL access token. Run: az login'
    }
    return $token.Trim()
}

# sqlsim timestamps every line and renders a result set as header / rule / rows /
# blank. Pull out just the row values so callers can compare them directly.
function ConvertFrom-SqlSimOutput {
    param([string]$Text)

    $values = New-Object System.Collections.Generic.List[string]
    $inRows = $false

    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw -replace '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \| ?', ''
        if ($line -match '^-{10,}$') { $inRows = $true; continue }
        if (-not $inRows) { continue }
        if ([string]::IsNullOrWhiteSpace($line)) { $inRows = $false; continue }
        $values.Add($line.TrimEnd())
    }
    return $values
}

function Invoke-Sql {
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$Database = $script:DatabaseName,
        [switch]$Raw
    )

    $out = & $script:SqlSim @(
        '-S', $script:ServerFqdn,
        '-d', $Database,
        '-T', (Get-SqlAccessToken),
        '-l', '60',
        '-stoponerror',
        '-Q', $Query
    ) 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0) {
        throw "sqlsim failed with exit code $LASTEXITCODE`n$out"
    }
    if ($Raw) { return $out.Trim() }
    return ((ConvertFrom-SqlSimOutput $out) -join "`n").Trim()
}

function Invoke-SqlFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Database = $script:DatabaseName,
        [hashtable]$Variables
    )

    if (-not (Test-Path $Path)) { throw "SQL file not found: $Path" }

    $target = $Path
    $temp   = $null

    # sqlsim has no sqlcmd-style -v, so expand $(name) before handing over the file.
    if ($Variables -and $Variables.Count -gt 0) {
        $text = Get-Content -LiteralPath $Path -Raw
        foreach ($key in $Variables.Keys) {
            $text = $text.Replace('$(' + $key + ')', [string]$Variables[$key])
        }
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("demo5-" + [System.Guid]::NewGuid().ToString('N') + '.sql')
        [System.IO.File]::WriteAllText($temp, $text, (New-Object System.Text.UTF8Encoding($false)))
        $target = $temp
    }

    try {
        $out = & $script:SqlSim @(
            '-S', $script:ServerFqdn,
            '-d', $Database,
            '-T', (Get-SqlAccessToken),
            '-l', '60',
            '-stoponerror',
            '-i', $target
        ) 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0) {
            throw "sqlsim failed on $(Split-Path $Path -Leaf) with exit code $LASTEXITCODE`n$out"
        }
        return $out.Trim()
    }
    finally {
        if ($temp -and (Test-Path $temp)) { Remove-Item $temp -Force }
    }
}
