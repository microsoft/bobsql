# Inventory reader/writer benchmark

Compare mixed reader/writer workloads under baseline locking, RCSI, ADR+RCSI,
and ADR+RCSI+optimized locking. Read the
[benchmark overview](../README.md) for configuration and dependencies.

Use SQL Server 2025, PowerShell, and `sqlsim.exe`. Inspect
[setup-inventory-all.ps1](setup-inventory-all.ps1) before creating the four
lab databases, then review [run-inventory-all.ps1](run-inventory-all.ps1) for
targets, concurrency, and duration. [check-blocking.sql](check-blocking.sql)
provides a companion observation.

These scripts create data and generate sustained load. Use a disposable
instance, capture comparable starting conditions, and review each setup's
database names before cleanup. [results](results/readme.md) contains previous
captures, not performance guarantees.
