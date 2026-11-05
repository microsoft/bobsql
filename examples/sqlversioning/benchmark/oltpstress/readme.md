# Write-only versioning benchmark

Compare INSERT/UPDATE/DELETE workload behavior across four versioning
configurations without readers. Start with the
[benchmark overview](../README.md).

Use SQL Server 2025, PowerShell, and `sqlsim.exe`. Inspect
[setup-stress-all.ps1](setup-stress-all.ps1), the configuration-specific setup
SQL, and workload JSON before running
[run-stress-all.ps1](run-stress-all.ps1).

The scripts create four lab databases and run write-heavy traffic. Confirm
instance names, available storage, concurrency, and duration first. Keep
starting conditions comparable and remove only the databases owned by the lab
when finished. [results](results/readme.md) contains captured example runs.
