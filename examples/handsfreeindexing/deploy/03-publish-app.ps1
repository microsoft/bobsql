[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
$null = Invoke-Az @('webapp', 'show', '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json')

$buildRoot = Join-Path ([IO.Path]::GetTempPath()) "caldova-hfi-publish-$PID"
$publishPath = Join-Path $buildRoot 'publish'
$packagePath = Join-Path $buildRoot 'caldova-hfi.zip'

try {
    New-Item -ItemType Directory -Path $publishPath -Force | Out-Null

    Write-Step 'Publishing the Blazor application'
    & dotnet publish $AppProject --configuration Release --output $publishPath
    if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }
    Write-Ok 'Release build complete'

    Compress-Archive -Path (Join-Path $publishPath '*') -DestinationPath $packagePath -CompressionLevel Optimal
    Write-Ok "Package created: $([math]::Round((Get-Item $packagePath).Length / 1MB, 2)) MB"

    Write-Step "Deploying package to $AppName"
    Invoke-Az @('webapp', 'deploy', '--resource-group', $ResourceGroup, '--name', $AppName,
        '--src-path', $packagePath, '--type', 'zip', '--clean', 'true', '--restart', 'true',
        '--async', 'false', '--output', 'json') | Out-Null
    Write-Ok 'Deployment completed'
}
finally {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nApplication published: $AppUrl" -ForegroundColor Green
Write-Host 'Next: run 04-verify.ps1.'
