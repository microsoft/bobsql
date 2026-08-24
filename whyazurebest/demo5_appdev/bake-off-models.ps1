# Measures how long each candidate chat model takes to triage a ticket, using
# the exact prompt the function app will ship. Run this before committing to a
# model -- the agent's answer lands on a slide behind the ticket card, so
# latency is a presentation decision, not just a cost one.
#
# Auth is the presenter's Entra token. No key, no connection string.

[CmdletBinding()]
param(
    [string]$AiAccount = 'bwappdev-ai',
    [string]$ApiVersion = '2025-04-01-preview',
    [string[]]$Models = @('gpt-5', 'gpt-5-mini', 'gpt-5-nano', 'gpt-4.1-mini')
)

. (Join-Path $PSScriptRoot '00-config.ps1')
. (Join-Path $PSScriptRoot 'tickets.ps1')

$Instructions = @'
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

# Reasoning models spend tokens thinking before they emit anything, so the
# floor is set by the model family, not by how short our answer is.
# 'minimal' is the lowest gpt-5 accepts ('none' arrived with gpt-5.1).
function Get-RequestBody {
    param([string]$Model, [string]$UserContent)

    $body = @{
        messages = @(
            @{ role = 'system'; content = $Instructions },
            @{ role = 'user'; content = $UserContent }
        )
        max_completion_tokens = 2000
        response_format       = @{ type = 'json_object' }
    }
    if ($Model -like 'gpt-5*') { $body.reasoning_effort = 'minimal' }
    return ($body | ConvertTo-Json -Depth 8)
}

function Format-Ticket {
    param($Ticket)
    return @"
Customer: $($Ticket.Customer)
Reported severity: $($Ticket.Severity)
Subject: $($Ticket.Subject)
Body: $($Ticket.Body)
"@
}

function Get-Percentile {
    param([double[]]$Values, [double]$Percentile)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = $Values | Sort-Object
    $index = [Math]::Ceiling(($Percentile / 100.0) * $sorted.Count) - 1
    if ($index -lt 0) { $index = 0 }
    return $sorted[$index]
}

Write-Beat 'Model bake-off: triage latency'

$endpoint = (Invoke-Az @('cognitiveservices', 'account', 'show', '-n', $AiAccount, '-g', $ResourceGroup)).properties.endpoint.TrimEnd('/')
Write-Ok $endpoint

$token = & az account get-access-token --resource 'https://cognitiveservices.azure.com/' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw 'Could not get a Cognitive Services token. Run: az login' }
$headers = @{ Authorization = "Bearer $($token.Trim())"; 'Content-Type' = 'application/json' }

$results = New-Object System.Collections.Generic.List[object]

foreach ($model in $Models) {
    Write-Step $model
    $uri = "$endpoint/openai/deployments/$model/chat/completions?api-version=$ApiVersion"

    # One throwaway call so route warm-up does not land in the sample.
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body (Get-RequestBody $model 'Subject: warm up. Body: ignore this ticket.') -TimeoutSec 180 | Out-Null
    }
    catch {
        Write-Fail "warm-up failed: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) { Write-Fail $_.ErrorDetails.Message }
        continue
    }

    foreach ($ticket in $script:Tickets) {
        $body = Get-RequestBody $model (Format-Ticket $ticket)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 180
            $sw.Stop()

            $content = $response.choices[0].message.content
            $parsed = $null
            try { $parsed = $content | ConvertFrom-Json } catch { }

            $results.Add([pscustomobject]@{
                    Model            = $model
                    Subject          = $ticket.Subject
                    Ms               = [Math]::Round($sw.Elapsed.TotalMilliseconds)
                    Action           = $parsed.action
                    Taken            = $parsed.taken
                    Severity         = $parsed.severity
                    ReasoningTokens  = $response.usage.completion_tokens_details.reasoning_tokens
                    CompletionTokens = $response.usage.completion_tokens
                    Ok               = ($null -ne $parsed.action)
                })
            Write-Skip ("  {0,6} ms  {1,-9} {2}" -f [Math]::Round($sw.Elapsed.TotalMilliseconds), $parsed.action, $parsed.taken)
        }
        catch {
            $sw.Stop()
            $detail = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
            Write-Fail "  $($ticket.Subject): $detail"
            $results.Add([pscustomobject]@{
                    Model = $model; Subject = $ticket.Subject; Ms = $null
                    Action = $null; Taken = $detail; Severity = $null
                    ReasoningTokens = $null; CompletionTokens = $null; Ok = $false
                })
        }
    }
}

Write-Beat 'Summary'

$summary = foreach ($group in ($results | Group-Object Model)) {
    $good = $group.Group | Where-Object Ok
    $ms = @($good.Ms | ForEach-Object { [double]$_ })
    [pscustomobject]@{
        Model     = $group.Name
        Ok        = "$($good.Count)/$($group.Group.Count)"
        MedianMs  = Get-Percentile $ms 50
        P90Ms     = Get-Percentile $ms 90
        MinMs     = if ($ms) { [Math]::Round(($ms | Measure-Object -Minimum).Minimum) } else { $null }
        MaxMs     = if ($ms) { [Math]::Round(($ms | Measure-Object -Maximum).Maximum) } else { $null }
        AvgReason = if ($good) { [Math]::Round((($good.ReasoningTokens | Measure-Object -Average).Average)) } else { $null }
    }
}

$summary | Sort-Object MedianMs | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$outFile = Join-Path $PSScriptRoot 'bake-off-results.json'
$results | ConvertTo-Json -Depth 6 | Set-Content -Path $outFile -Encoding utf8
Write-Ok "Detail written to $outFile"
Write-Skip 'n=10 per model, so treat P90 as "worst realistic case", not a true tail.'
