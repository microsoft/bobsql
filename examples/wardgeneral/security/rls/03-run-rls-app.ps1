<#
.SYNOPSIS
    Start the cumulative Ward General application with all Security features visible.

.DESCRIPTION
    Runs the existing Ward General App restart entry point visibly in the foreground
    with AI-Ready SQL AI assistance, the Agentic AI agent, and Security RLS enabled.
    Start 02-run-secured-dab.ps1 in another terminal first. Ctrl+C stops the app.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [switch] $NoBrowser,
    [switch] $SkipFirewall,
    [switch] $SkipPreflight
)

$ErrorActionPreference = 'Stop'
$restart = Join-Path $PSScriptRoot '..' '..' 'first-app' 'restart.ps1'
$arguments = @{
    Enable = @('AiAssistance', 'AiAgent', 'RowLevelSecurity')
    NoBrowser = $NoBrowser
    SkipFirewall = $SkipFirewall
    SkipPreflight = $SkipPreflight
}
if ($Server) { $arguments.Server = $Server }
if ($Database) { $arguments.Database = $Database }

& $restart @arguments
