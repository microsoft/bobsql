[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
dotnet run --project (Join-Path $PSScriptRoot 'Caldova.TransferCenter.csproj') --launch-profile http