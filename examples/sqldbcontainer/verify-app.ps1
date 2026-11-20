#requires -Version 7.0
<#
.SYNOPSIS
Exercises the running web app, SQL masking, JSON filtering, prepared searches,
input validation, and anti-forgery enforcement without changing any case.
#>
[CmdletBinding()]
param([uri]$BaseUri = 'http://localhost:5187')
$ErrorActionPreference = 'Stop'
function Get-Page {
    param([string]$Path)
    Invoke-WebRequest -Uri ([uri]::new($BaseUri, $Path)) -SkipHttpErrorCheck -SessionVariable session
}
function Assert-Response {
    param($Response, [int]$Status, [string]$Pattern, [string]$Name)
    if ($Response.StatusCode -ne $Status -or [Net.WebUtility]::HtmlDecode($Response.Content) -notmatch $Pattern) {
        throw "$Name failed: HTTP $($Response.StatusCode), expected $Status and required content."
    }
    Write-Host "PASS: $Name"
}
Assert-Response -Response (Get-Page '/health') -Status 200 -Pattern '"database":"reachable"' -Name 'Database health'
Assert-Response -Response (Get-Page '/') -Status 200 -Pattern 'A clearer path to resolution' -Name 'Case workspace'
$workspace = Get-Page '/'
Assert-Response -Response $workspace -Status 200 -Pattern "JSON_VALUE\(c\.Details, '\$\.channel'\) = @Channel" -Name 'Contact channel tooltip explains the SQL JSON predicate'
Assert-Response -Response $workspace -Status 200 -Pattern 'aria-describedby="filter-query-tooltip">Apply filters</button>' -Name 'Apply filters button exposes its SQL tooltip to keyboard users'
$environmentPage = Get-Page '/Environment'
$headerVersion = [regex]::Match($workspace.Content, 'engine-version-label">@@VERSION</span><pre[^>]*>(.*?)</pre>', 'Singleline')
$detailVersion = [regex]::Match($environmentPage.Content, '<h2>Engine version</h2><pre>(.*?)</pre>', 'Singleline')
if (-not $headerVersion.Success -or -not $detailVersion.Success -or
    $headerVersion.Groups[1].Value -cne $detailVersion.Groups[1].Value) {
    throw 'Header must display the complete live engine version, matching the Environment page.'
}
Write-Host 'PASS: Full live @@VERSION beside the environment label'
$filtered = Get-Page '/?Status=Open&Channel=chat'
Assert-Response -Response $filtered -Status 200 -Pattern 'badge open' -Name 'SQL status and JSON channel filters'
if ($filtered.Content -match 'badge resolved|badge inprogress|<td>phone</td>|<td>web</td>') {
    throw 'SQL filters returned a mismatched status or JSON channel.'
}
Assert-Response -Response (Get-Page '/?Status=invalid') -Status 400 -Pattern 'validation' -Name 'Invalid filter rejection'
$detail = Get-Page '/Cases/Details/1'
Assert-Response -Response $detail -Status 200 -Pattern '\*{5}@example\.test' -Name 'SQL-enforced email mask'
if ($detail.Content -match 'customer\d+@example\.test|\+1 202-555') {
    throw 'The case detail page exposed an unmasked customer contact.'
}
Assert-Response -Response $detail -Status 200 -Pattern '\(\+1\)-xxxx' -Name 'SQL-enforced phone mask'
$decodedDetail = [Net.WebUtility]::HtmlDecode($detail.Content)
$schema = Get-Content -LiteralPath (Join-Path $PSScriptRoot '04-create-schema.sql') -Raw
foreach ($column in @('Email', 'Phone')) {
    $definition = [regex]::Match($schema, "$column varchar\(\d+\) MASKED WITH \(FUNCTION = '([^']+)'\)")
    if (-not $definition.Success -or -not $decodedDetail.Contains("<code>$($definition.Groups[1].Value)</code>")) {
        throw "$column tooltip does not match the SQL masking definition."
    }
}
Write-Host 'PASS: Email and phone hover tooltips match SQL regex mask definitions'
Assert-Response -Response (Get-Page '/Cases/Details/2147483647') -Status 404 -Pattern '' -Name 'Unknown case returns 404'
$search = Get-Page '/Search'
Assert-Response -Response $search -Status 200 -Pattern 'Prepared dropdown: no live model call' -Name 'Explicit prepared-query labeling'
$queryTooltip = [regex]::Match($search.Content, '(?s)id="vector-query-tooltip".*?<code>(.*?)</code>')
$vectorSchema = Get-Content -LiteralPath (Join-Path $PSScriptRoot '04-create-schema.sql') -Raw
$actualQuery = [regex]::Match($vectorSchema, '(?s)SELECT TOP \(@Take\) WITH APPROXIMATE.*?ORDER BY s.distance;')
if (-not $queryTooltip.Success -or -not $actualQuery.Success -or
    (([Net.WebUtility]::HtmlDecode($queryTooltip.Groups[1].Value) -replace '\s+', ' ').Trim() -cne
     ($actualQuery.Value -replace '\s+', ' ').Trim())) {
    throw 'VECTOR_SEARCH tooltip does not match the actual shared SQL query.'
}
Write-Host 'PASS: Search resolved cases tooltip matches the actual VECTOR_SEARCH query'
$ids = [regex]::Matches($search.Content, '<option value="(\d+)"[^>]*>') |
    ForEach-Object { [int]$_.Groups[1].Value }
if ($ids.Count -lt 6) { throw 'Fewer than six prepared searches were exposed.' }
foreach ($option in [regex]::Matches($search.Content, '<option value="\d+"[^>]*>(.*?)</option>')) {
    $question = [Net.WebUtility]::HtmlDecode($option.Groups[1].Value)
    if (($question -split '\s+').Count -gt 8) { throw "Prepared question exceeds eight words: $question" }
}
Write-Host 'PASS: Prepared dropdown questions are at most eight words'
foreach ($id in $ids) {
    $result = Get-Page "/Search?QueryId=$id"
    Assert-Response -Response $result -Status 200 -Pattern '5 related resolutions' -Name "Prepared search $id"
    if ([regex]::Matches($result.Content, 'COSINE DISTANCE').Count -ne 5) {
        throw "Prepared search $id did not render five distances."
    }
}
if ([regex]::Matches($search.Content, '<form\b').Count -ne 1 -or $search.Content -notmatch '<input[^>]*id="QueryText"') {
    throw 'Related cases must have one search form with an editable text input.'
}
$example = [regex]::Match($search.Content, '<option value="\d+"[^>]*data-question="([^"]*)"')
$examplePage = Invoke-WebRequest ([uri]::new($BaseUri, '/Search')) -SessionVariable exampleBrowser
$exampleToken = [regex]::Match($examplePage.Content, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"')
$exampleResult = Invoke-WebRequest ([uri]::new($BaseUri, '/Search')) -Method Post -WebSession $exampleBrowser `
    -Body @{ '__RequestVerificationToken' = $exampleToken.Groups[1].Value;
        QueryText = [Net.WebUtility]::HtmlDecode($example.Groups[1].Value) } -SkipHttpErrorCheck
Assert-Response -Response $exampleResult -Status 200 -Pattern 'PREPARED EMBEDDING \+ LIVE SQL SEARCH' -Name 'Unified text box preserves exact prepared-example path'
Assert-Response -Response $exampleResult -Status 200 -Pattern 'id="search-results"' -Name 'Results have a visible navigation target'
Assert-Response -Response (Get-Page '/Search?QueryId=2147483647') -Status 400 -Pattern 'valid prepared search' -Name 'Unknown search rejection'
$liveCases = @(
    @{ Query = 'Documents are stuck waiting and no paper emerges after we changed the network equipment.';
       Topic = 'printer-offline'; NovelWords = @('paper', 'emerges', 'equipment') },
    @{ Query = 'My online drive says there is no room, even after I threw away a lot of documents.';
       Topic = 'storage-full'; NovelWords = @('online', 'room', 'threw', 'documents') }
)
foreach ($test in $liveCases) {
    $form = Invoke-WebRequest ([uri]::new($BaseUri, '/Search')) -SessionVariable searchBrowser
    $searchToken = [regex]::Match($form.Content, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"')
    if (-not $searchToken.Success) { throw 'Free-text search form has no anti-forgery token.' }
    if ($form.Content -match [regex]::Escape($test.Query)) { throw 'Live verification must use a question outside the prepared dropdown.' }
    $live = Invoke-WebRequest ([uri]::new($BaseUri, '/Search')) -Method Post -WebSession $searchBrowser `
        -Body @{ '__RequestVerificationToken' = $searchToken.Groups[1].Value; QueryText = $test.Query } `
        -TimeoutSec 90 -SkipHttpErrorCheck
    Assert-Response -Response $live -Status 200 -Pattern 'LIVE OLLAMA EMBEDDING \+ SQL SEARCH' -Name "Live question: $($test.Topic)"
    $articles = [regex]::Matches($live.Content, '(?s)<article class="panel padded search-result">(.*?)</article>')
    if ($articles.Count -ne 5 -or @($articles | Where-Object { $_.Value -match [regex]::Escape($test.Topic) }).Count -ne 5) {
        throw "Live question did not return five expected-topic cases: $($test.Topic)."
    }
    $plainResults = ($articles.Value -join ' ') -replace '<[^>]+>', ' '
    $resultText = [Net.WebUtility]::HtmlDecode($plainResults)
    foreach ($word in $test.NovelWords) {
        if ($resultText -match "\b$([regex]::Escape($word))\b") {
            throw "Semantic demo keyword '$word' unexpectedly appears in the displayed results."
        }
    }
    Write-Host "PASS: Five $($test.Topic) results without prompt words $($test.NovelWords -join ', ')"
}
$emptySearch = Invoke-WebRequest ([uri]::new($BaseUri, '/Search')) -Method Post -WebSession $searchBrowser `
    -Body @{ '__RequestVerificationToken' = $searchToken.Groups[1].Value; QueryText = '   ' } -SkipHttpErrorCheck
Assert-Response -Response $emptySearch -Status 400 -Pattern 'QueryText field is required' -Name 'Empty free-text question rejection'
$environment = Get-Page '/Environment'
Assert-Response -Response $environment -Status 200 -Pattern 'CustomerServiceDeskWeb' -Name 'Restricted runtime database identity'
Assert-Response -Response $environment -Status 200 -Pattern '<dt>UNMASK permission</dt><dd>0</dd>' -Name 'No UNMASK permission'
Assert-Response -Response $environment -Status 200 -Pattern '<dt>Direct customer SELECT</dt><dd>0</dd>' -Name 'No direct customer SELECT'
Assert-Response -Response $environment -Status 200 -Pattern '<dt>DiskANN index version</dt><dd>3</dd>' -Name 'Current DiskANN index metadata'
$create = Invoke-WebRequest ([uri]::new($BaseUri, '/Cases/Create')) -SessionVariable browser
Assert-Response -Response $create -Status 200 -Pattern 'name="Input.Title"' -Name 'Case editor field binding'
$tokenMatch = [regex]::Match($create.Content, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"')
if (-not $tokenMatch.Success) { throw 'Create page has no anti-forgery token.' }
$invalid = Invoke-WebRequest ([uri]::new($BaseUri, '/Cases/Create')) -Method Post -WebSession $browser `
    -Body @{ '__RequestVerificationToken' = $tokenMatch.Groups[1].Value; CustomerId = 1;
        'Input.Title' = 'Verification must not create this'; 'Input.Description' = 'Synthetic input validation';
        'Input.Topic' = 'general'; 'Input.Status' = 'Open'; 'Input.Priority' = 'Normal';
        'Input.Details' = '{"channel":"invalid"}' } -SkipHttpErrorCheck
Assert-Response -Response $invalid -Status 400 -Pattern 'Include a channel of web, phone, or chat' -Name 'JSON validation blocks invalid save'
$noToken = Invoke-WebRequest ([uri]::new($BaseUri, '/Cases/Create')) -Method Post `
    -Body @{ CustomerId = 1 } -SkipHttpErrorCheck
Assert-Response -Response $noToken -Status 400 -Pattern '' -Name 'Anti-forgery rejects untrusted save'
Write-Host 'Web verification passed. No case data was changed.'
