[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = 'Stop'
throw 'Full teardown is disabled: preserve both logical servers and their cross-database preview settings. Use 10-reset-part1.ps1 for an explicitly approved Start database-only reset.'
