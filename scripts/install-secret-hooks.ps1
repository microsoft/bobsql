$ErrorActionPreference = 'Stop'
$shellCommand = Get-Command sh -ErrorAction SilentlyContinue
if ($shellCommand) {
    $shell = $shellCommand.Source
}
else {
    $gitExecPath = git --exec-path
    if ($LASTEXITCODE -ne 0) { throw 'Git is required.' }
    $gitRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gitExecPath))
    $shell = Join-Path $gitRoot 'bin\sh.exe'
    if (-not (Test-Path -LiteralPath $shell)) {
        throw 'Git shell not found. Run sh scripts/install-secret-hooks.sh in Git Bash.'
    }
}
& $shell (Join-Path $PSScriptRoot 'install-secret-hooks.sh')
if ($LASTEXITCODE -ne 0) { throw 'Secret hook installation failed.' }
