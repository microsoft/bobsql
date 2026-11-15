[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$destinationRoot = [IO.Path]::GetFullPath($Destination)

if ($destinationRoot.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination must be outside the source demo folder.'
}
if (Test-Path -LiteralPath $destinationRoot) {
    if (Get-ChildItem -LiteralPath $destinationRoot -Force | Select-Object -First 1) {
        throw "Destination must be empty: '$destinationRoot'."
    }
}
else {
    [void][IO.Directory]::CreateDirectory($destinationRoot)
}

$publicItems = @(
    'app',
    'architecture',
    'database',
    'hyperscale-foundry',
    'setup',
    'DEMO-RUNBOOK.md',
    'Publish-Demo.ps1',
    'README.md',
    '.gitignore'
)

foreach ($item in $publicItems) {
    $source = Join-Path $sourceRoot $item
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required public item is missing: '$source'."
    }

    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination $destinationRoot
        continue
    }

    Get-ChildItem -LiteralPath $source -Recurse -File -Force |
        Where-Object {
            $_.FullName -notmatch '[\\/](bin|obj|node_modules|exports|\.git)[\\/]' -and
            $_.Name -notmatch '(?i)kubeconfig|^appsettings\.(Local|.*\.local)\.json$' -and
            ($_.Extension -in '.md', '.ps1', '.sql', '.json', '.cs', '.csproj',
                '.css', '.js', '.cjs', '.html', '.yaml' -or $_.Name -eq '.gitignore')
        } |
        ForEach-Object {
            $relativePath = [IO.Path]::GetRelativePath($sourceRoot, $_.FullName)
            $targetPath = Join-Path $destinationRoot $relativePath
            [void][IO.Directory]::CreateDirectory((Split-Path $targetPath))
            Copy-Item -LiteralPath $_.FullName -Destination $targetPath
        }
}

$forbidden = Get-ChildItem -LiteralPath $destinationRoot -Recurse -File |
    Where-Object {
        $_.FullName -match '[\\/](bin|obj)[\\/]' -or
        $_.Extension -in '.kubeconfig', '.pfx', '.key'
    }
if ($forbidden) {
    throw "Forbidden files were copied:`n$($forbidden.FullName -join [Environment]::NewLine)"
}

Write-Host "Source package created at '$destinationRoot'." -ForegroundColor Green
Write-Warning 'Copying is not sanitization. Review local edits and run a redacted secret scan before publishing.'