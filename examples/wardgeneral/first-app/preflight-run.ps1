#requires -Version 7.0
<#
    Ward General Hospital Digital Chart Application
    preflight-run.ps1 : check that the app can REACH ITS DATA before it starts.

    Everything here is about the path from this machine to Azure SQL. None of
    it is needed to compile the solution -- see preflight-build.ps1 for that.

    Checks:
      1. Azure sign-in   az installed, and `az login` done   (failure)
      2. Firewall        this client's IP is allowed through (delegated)
      3. Database        reachable, Getting Started schema + data  (failure)
      4. SQL MCP         Agentic AI endpoint serving its tools (failure, and only
                         when the AiAgent feature flag is on)

    Why these are failures rather than warnings: the app authenticates with
    DefaultAzureCredential, which uses the same sign-in as the Azure CLI.
    Without it, Kestrel starts, the page renders -- and the first data load
    throws. The error surfaces as an application bug, pages away from its real
    cause. Catching it here is the whole point.

    run.ps1 calls this automatically. Exit code 0 = ready. 1 = a failure.

    With no arguments the server and database come from the same places the app
    itself reads them, highest first: the WardGeneral__Server / WardGeneral__Database
    environment variables -- which wardgeneral.env populates, if you made one -- then
    src/WardGeneral.Web/appsettings.Development.json, then appsettings.json. Pass
    them explicitly to override.

    appsettings.json ships with an EMPTY server on purpose -- no live server name is
    ever the committed default. Supplying one is the reader's first job.

    Usage:
      ./preflight-run.ps1
      ./preflight-run.ps1 -SkipFirewall
      ./preflight-run.ps1 -Server <your-server> -Database <your-database>
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$Database,
    [switch]$SkipFirewall
)

$root = $PSScriptRoot
$failures = 0
$warnings = 0

function Write-Check {
    param([ValidateSet('pass', 'warn', 'fail', 'skip')][string]$Result, [string]$Name, [string]$Detail)
    $mark, $color = switch ($Result) {
        'pass' { '  OK  ', 'Green' }
        'warn' { ' WARN ', 'Yellow' }
        'fail' { ' FAIL ', 'Red' }
        'skip' { ' SKIP ', 'DarkGray' }
    }
    Write-Host "[$mark] " -ForegroundColor $color -NoNewline
    Write-Host $Name -NoNewline
    if ($Detail) { Write-Host " - $Detail" -ForegroundColor DarkGray } else { Write-Host '' }
}

Write-Host "`nWard General - run pre-flight`n" -ForegroundColor Cyan

# wardgeneral.env, if the reader made one. -Optional means "absent is fine" -- Ward General App
# has two other ways to configure the connection and neither is worse. This runs
# before the chain below so the file lands in the environment-variable layer,
# which is where the app itself looks first.
& (Join-Path $root 'load-env.ps1') -Optional -Quiet

# One source of truth for where the app points: the same configuration chain the
# app itself reads, in the same order. Parameters override everything.
$webDir = Join-Path $root 'src' 'WardGeneral.Web'
if (-not $Server -or -not $Database) {
    function Read-Setting {
        param([string]$File, [string]$Name)
        $path = Join-Path $webDir $File
        if (-not (Test-Path $path)) { return $null }
        $value = (Get-Content $path -Raw | ConvertFrom-Json).WardGeneral.$Name
        if ([string]::IsNullOrWhiteSpace($value)) { return $null } else { return $value }
    }

    if (-not $Server) {
        $Server = $env:WardGeneral__Server ?? (Read-Setting 'appsettings.Development.json' 'Server') `
            ?? (Read-Setting 'appsettings.json' 'Server')
    }
    if (-not $Database) {
        $Database = $env:WardGeneral__Database ?? (Read-Setting 'appsettings.Development.json' 'Database') `
            ?? (Read-Setting 'appsettings.json' 'Database')
    }
}

if (-not $Server) {
    Write-Check fail 'Configuration' 'no server configured'
    Write-Host ''
    Write-Host '  Point the app at your Hyperscale database in any one of these:' -ForegroundColor Yellow
    Write-Host '    wardgeneral.env                                          (copy wardgeneral.env.template)' -ForegroundColor DarkGray
    Write-Host '    ./run.ps1 -Server <your-server>.database.windows.net' -ForegroundColor DarkGray
    Write-Host '    $env:WardGeneral__Server = ''<your-server>.database.windows.net''' -ForegroundColor DarkGray
    Write-Host '    src/WardGeneral.Web/appsettings.Development.json  (git-ignored)' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

# -- 1. Azure sign-in -------------------------------------------------------
$signedIn = $false
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Check fail 'Azure CLI' 'not found on PATH - see https://aka.ms/installazurecli'
    $failures++
}
else {
    $acct = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $acct) {
        Write-Check fail 'Azure sign-in' "not signed in - run 'az login'"
        $failures++
    }
    else {
        # Print what we found. A reader signed in to the wrong tenant sees a
        # permissions error later that looks nothing like the real cause.
        Write-Check pass 'Azure sign-in' "$($acct.user.name) / $($acct.name)"
        $signedIn = $true
    }
}

# -- 2. Firewall ------------------------------------------------------------
# Delegated to Getting Started's script, which detects this client's public IP and
# PROMPTS before adding a single named rule (it never opens 0.0.0.0).
if ($SkipFirewall) {
    Write-Check skip 'Firewall' '-SkipFirewall'
}
elseif (-not $signedIn) {
    Write-Check skip 'Firewall' 'needs an Azure sign-in first'
}
else {
    $fwScript = Join-Path $root '..' 'getting-started' 'preflight-firewall.ps1'
    if (-not (Test-Path $fwScript)) {
        Write-Check warn 'Firewall' "Getting Started script not found at $fwScript"
        $warnings++
    }
    else {
        # Let its output through: this script can PROMPT to add a rule, and a
        # swallowed prompt looks like a hang.
        & $fwScript -Server (([string]$Server).Split('.')[0])
        switch ($LASTEXITCODE) {
            0 { Write-Check pass 'Firewall' 'this client is allowed through' }
            1 {
                Write-Check warn 'Firewall' 'declined or skipped - connections may fail'
                $warnings++
            }
            default {
                Write-Check warn 'Firewall' "check could not run (exit $LASTEXITCODE)"
                $warnings++
            }
        }
        $global:LASTEXITCODE = 0
    }
}

# -- 3. Database ------------------------------------------------------------
if (-not $signedIn) {
    Write-Check skip 'Database' 'needs an Azure sign-in first'
}
elseif (-not $Server -or -not $Database) {
    Write-Check fail 'Database' 'could not determine server/database - pass -Server and -Database'
    $failures++
}
else {
    $isGoSqlcmd = {
        param([string] $Executable)
        if (-not $Executable) { return $false }
        & $Executable --version 2>&1 | Out-Null
        return $LASTEXITCODE -eq 0
    }
    $sqlcmdPath = @(
        $env:SQLCMD,
        (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
        'C:\Program Files\SqlCmd\sqlcmd.exe',
        (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
    ) | Where-Object { $_ -and (Test-Path $_) -and (& $isGoSqlcmd $_) } |
        Select-Object -First 1

    if (-not $sqlcmdPath) {
        Write-Check warn 'Database' 'Go-based sqlcmd not found - install Microsoft.Sqlcmd and re-run'
        $warnings++
    }
    else {
        try {
            $queryPath = Join-Path $root 'preflight-database.sql'
            $result = @(& $sqlcmdPath -S $Server -d $Database -G -C -b `
                -h -1 -W -s '|' -i $queryPath
            )
            if ($LASTEXITCODE -ne 0) { throw "sqlcmd exited with code $LASTEXITCODE" }
            $row = [string] ($result | Where-Object { $_ -match '\|' } | Select-Object -Last 1)
            $values = $row.Split('|')
            if ($values.Count -ne 2) { throw "unexpected database preflight output: $result" }
            $hasSchema = [int] $values[0].Trim() -eq 1
            $patients = [int] $values[1].Trim()

            if (-not $hasSchema) {
                Write-Check fail 'Database' 'connected, but the Getting Started schema is missing - run the Getting Started schema scripts'
                $failures++
            }
            elseif ($patients -le 0) {
                Write-Check fail 'Database' 'schema is there but no patients - run the Getting Started seed script'
                $failures++
            }
            else {
                Write-Check pass 'Database' "$Database on $Server - schema present, $patients patients"
            }
        }
        catch {
            Write-Check fail 'Database' $_.Exception.Message
            $failures++
        }
    }
}

# -- 4. SQL MCP endpoint ----------------------------------------------------
# Only when the AiAgent flag is on. Ward General App and AI-Ready SQL readers never see
# this check; for them the endpoint is not part of the app.
#
# It is a FAILURE rather than a warning because of what the flag means. Asking
# for the agent and getting an agent with no tools is worse than not starting:
# the chat panel opens, the model answers from nothing, and the reader debugs a
# prompt when the real problem is that a second process was never started.
$agentOn = $false
if ($env:Features__AiAgent) {
    $agentOn = $env:Features__AiAgent -eq 'true'
}
else {
    foreach ($f in 'appsettings.Development.json', 'appsettings.json') {
        $p = Join-Path $webDir $f
        if (Test-Path $p) {
            $v = (Get-Content $p -Raw | ConvertFrom-Json).Features.AiAgent
            if ($null -ne $v) { $agentOn = [bool]$v; break }
        }
    }
}

if (-not $agentOn) {
    Write-Check skip 'SQL MCP endpoint' 'AiAgent flag is off'
}
else {
    $mcpUrl = $env:Agent__McpUrl
    if (-not $mcpUrl) {
        foreach ($f in 'appsettings.Development.json', 'appsettings.json') {
            $p = Join-Path $webDir $f
            if (Test-Path $p) {
                $v = (Get-Content $p -Raw | ConvertFrom-Json).Agent.McpUrl
                if (-not [string]::IsNullOrWhiteSpace($v)) { $mcpUrl = $v; break }
            }
        }
    }
    if (-not $mcpUrl) { $mcpUrl = 'http://localhost:5000/mcp' }

    $rlsOn = $env:RowLevelSecurity__Enabled -eq 'true'
    $probe = if ($rlsOn) {
        Join-Path $root '..' 'security' 'rls' 'probe-secured-mcp.ps1'
    }
    else {
        Join-Path $root '..' 'agentic-ai' 'probe-mcp.ps1'
    }
    if (-not (Test-Path $probe)) {
        Write-Check warn 'SQL MCP endpoint' "MCP probe not found at $probe"
        $warnings++
    }
    else {
        $tools = & $probe -Url $mcpUrl -Quiet
        if ($LASTEXITCODE -ne 0 -or -not $tools) {
            Write-Check fail 'SQL MCP endpoint' "nothing answering at $mcpUrl"
            Write-Host ''
            Write-Host '  The AiAgent flag is on, so the app needs its SQL MCP server.' -ForegroundColor Yellow
            Write-Host '  Start it in its own shell, and wait for it to bind, before starting the app:' -ForegroundColor Yellow
            if ($rlsOn) {
                Write-Host '    ./security/rls/02-run-secured-dab.ps1' -ForegroundColor DarkGray
            }
            else {
                Write-Host '    ./agentic-ai/run-dab.ps1' -ForegroundColor DarkGray
            }
            Write-Host ''
            $failures++
            $global:LASTEXITCODE = 0
        }
        else {
            # 7 is the whole inventory, and it is only 7 because dab-config.primary.json
            # sets runtime.mcp.dml-tools to false. If DAB's seven generic tools come
            # back, execute_entity is among them - and it can reach the approval-gated
            # write by name, around the application's gate. Catch that here, once,
            # rather than never.
            if ($tools.Count -eq 7) {
                Write-Check pass 'SQL MCP endpoint' "$mcpUrl - 7 tools"
            }
            else {
                Write-Check warn 'SQL MCP endpoint' "$mcpUrl - $($tools.Count) tools, expected 7"
                Write-Host '        Check runtime.mcp.dml-tools in dab-config.primary.json.' -ForegroundColor DarkGray
                $warnings++
            }
        }
    }
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host "Run pre-flight failed: $failures problem(s) to fix before the app will work.`n" -ForegroundColor Red
    exit 1
}
elseif ($warnings -gt 0) {
    Write-Host "Run pre-flight passed with $warnings warning(s).`n" -ForegroundColor Yellow
}
else {
    Write-Host "Run pre-flight passed.`n" -ForegroundColor Green
}
exit 0
