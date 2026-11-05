$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('bobsql-hook-test-' + [guid]::NewGuid().ToString('N'))
$shellCommand = Get-Command sh -ErrorAction SilentlyContinue
if ($shellCommand) {
    $shell = $shellCommand.Source
}
else {
    $gitExecPath = git --exec-path
    if ($LASTEXITCODE -ne 0) { throw 'Git is required.' }
    $gitRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gitExecPath))
    $shell = Join-Path $gitRoot 'bin\sh.exe'
    if (-not (Test-Path -LiteralPath $shell)) { throw 'Git shell not found.' }
}

function Assert-Exit([string] $Name, [int] $Expected, [scriptblock] $Run) {
    & $Run | Out-Null
    if ($LASTEXITCODE -ne $Expected) {
        throw "$Name failed: expected exit $Expected, got $LASTEXITCODE"
    }
    Write-Output "PASS: $Name"
}

function Write-Fixture([string] $Name, [string] $Content) {
    [System.IO.File]::WriteAllText((Join-Path $fixture $Name), $Content)
}

function Invoke-PushHook([string] $InputLine) {
    # Match Git's LF-only hook protocol, not PowerShell's CRLF pipeline.
    Write-Fixture '.git\test-push-input' ($InputLine + "`n")
    & $shell -c '.githooks/pre-push < .git/test-push-input'
}

New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $root '.githooks') -Destination $fixture -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'scripts') -Destination $fixture -Recurse
    Copy-Item -LiteralPath (Join-Path $root '.gitleaks.toml') -Destination $fixture
    Push-Location $fixture
    try {
        git init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Fixture initialization failed.' }
        git config user.name 'Hook Test'
        git config user.email 'hook-test@example.invalid'
        git config commit.gpgsign false
        Assert-Exit 'Hook installation' 0 { & $shell scripts/install-secret-hooks.sh }
        if ((git config --local --get core.hooksPath) -ne '.githooks') {
            throw 'Hook installation did not persist.'
        }

        Write-Fixture 'sample.txt' 'Clean demo content'
        git add sample.txt
        Assert-Exit 'Clean commit' 0 { git commit --quiet -m 'Clean fixture' }
        $clean = git rev-parse HEAD
        $zero = '0' * $clean.Length

        $samples = @{
            'SQL credential' = ("SE" + "CRET = 'synthetic-credential-only'")
            'sqlcmd argument' = ('sqlcmd -S localhost -' + 'P synthetic-password-only')
            'Attached sqlcmd argument' = ('sqlcmd -S localhost -' + 'Psynthetic-password-only')
            'Quoted PowerShell argument' = ("sqlcmd '-Slocalhost' '-" + "Psynthetic-password-only'")
            'Unicode SQL password' = ('CREATE LOGIN test WITH PASS' + "WORD = N'synthetic-password-only';")
            'SQL password variable' = ('SET @distributorpass' + "word = N'synthetic-password-only';")
            'Container password' = ('MSSQL_SA_' + 'PASSWORD: synthetic-password-only')
            'Shell password assignment' = ('SQLCMDPASS' + 'WORD=synthetic-password-only')
            'GitHub token' = ('gh' + 'p_' + '1234567890abcdef1234567890abcdef123456')
        }
        foreach ($sample in $samples.GetEnumerator()) {
            Write-Fixture 'sample.txt' $sample.Value
            git add sample.txt
            Assert-Exit "$($sample.Key) blocks commit" 1 { git commit --quiet -m 'Must be blocked' }
        }

        $safeSamples = @(
            'SET @password = @distributorpassword;'
            'CREATE LOGIN test WITH PASSWORD = ''$(SqlLoginPassword)'';'
            ': "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately}"'
            'SQLCMDPASSWORD="${MSSQL_SA_PASSWORD:?Set a private value}"'
            'MSSQL_SA_PASSWORD: "${SQLCMDPASSWORD:?Set a private value}"'
            'kubectl create secret generic demo --from-file=SA_PASSWORD=/dev/stdin'
            'data = @{ SA_PASSWORD = [Convert]::ToBase64String($bytes) }'
            'sqlcmd -S localhost -U sa -b'
        )
        Write-Fixture 'sample.txt' ($safeSamples -join "`n")
        git add sample.txt
        Assert-Exit 'Runtime credential references pass commit' 0 { git commit --quiet -m 'Safe runtime inputs' }

        $credential = ('Pass' + 'word') + '=synthetic-test-value-only'
        Write-Fixture 'sample.txt' $credential
        git add sample.txt
        Assert-Exit 'Staged password blocks commit' 1 { git commit --quiet -m 'Must be blocked' }

        # A clean worktree must not hide a secret already in the index.
        Write-Fixture 'sample.txt' 'Clean worktree, unsafe index'
        Assert-Exit 'Partially staged password blocks commit' 1 { git commit --quiet -m 'Must still be blocked' }
        git add sample.txt
        Assert-Exit 'Clean staged content ignores unstaged secret' 0 {
            Write-Fixture 'sample.txt' $credential
            git commit --quiet -m 'Clean index only'
        }

        git add sample.txt
        # Create unsafe historical commits only inside this disposable test repository.
        git -c core.hooksPath=unused-test-hooks commit --quiet -m 'Synthetic historical leak'
        if ($LASTEXITCODE -ne 0) { throw 'Historical fixture creation failed.' }
        Write-Fixture 'sample.txt' 'Secret removed'
        git add sample.txt
        git -c core.hooksPath=unused-test-hooks commit --quiet -m 'Remove synthetic leak'
        if ($LASTEXITCODE -ne 0) { throw 'Historical cleanup fixture creation failed.' }
        $tip = git rev-parse HEAD
        Assert-Exit 'Outgoing added-then-removed password blocks push' 1 {
            Invoke-PushHook "refs/heads/test $tip refs/heads/test $clean"
        }
        Assert-Exit 'New remote ref scans historical secrets' 1 {
            Invoke-PushHook "refs/heads/test $tip refs/heads/new $zero"
        }
        $remote = Join-Path $fixture '.git\test-remote.git'
        git init --bare --quiet $remote
        if ($LASTEXITCODE -ne 0) { throw 'Local push destination initialization failed.' }
        Assert-Exit 'Real git push invokes hook and blocks leaked history' 1 {
            git push --quiet $remote "${tip}:refs/heads/test"
        }
        $published = git --git-dir=$remote for-each-ref --format='%(refname)'
        if ($published) { throw 'Blocked push published a ref.' }
        Assert-Exit 'Real clean git push succeeds' 0 {
            git push --quiet $remote "${clean}:refs/heads/test"
        }
        Assert-Exit 'Clean outgoing ref passes' 0 {
            Invoke-PushHook "refs/heads/test $clean refs/heads/test $zero"
        }
        Assert-Exit 'Ref deletion passes' 0 {
            Invoke-PushHook "(delete) $zero refs/heads/test $tip"
        }
        $unknown = '1' * $clean.Length
        Assert-Exit 'Unavailable remote base blocks push' 1 {
            Invoke-PushHook "refs/heads/test $tip refs/heads/test $unknown"
        }
        Assert-Exit 'Missing scanner blocks scan' 1 {
            & $shell -c 'PATH=/nonexistent; export PATH; . ./scripts/check-secrets.sh staged'
        }
        Assert-Exit 'Missing scanner blocks hook installation' 1 {
            & $shell -c 'PATH=/nonexistent; export PATH; . ./scripts/install-secret-hooks.sh'
        }
        Write-Fixture '.gitleaks.toml' 'not valid TOML = ['
        Assert-Exit 'Scanner configuration errors block commit' 1 {
            git commit --quiet --allow-empty -m 'Invalid scanner must block'
        }
        git config --local core.hooksPath existing-test-hooks
        Assert-Exit 'Installer preserves existing hooks configuration' 1 { & $shell scripts/install-secret-hooks.sh }
        if ((git config --local --get core.hooksPath) -ne 'existing-test-hooks') {
            throw 'Existing hooks configuration was overwritten.'
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
