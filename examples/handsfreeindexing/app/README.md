# Caldova Patient Access Operations

A .NET 10 Blazor Server application for the live Azure SQL hands-free indexing lifecycle.

- **Operations Dashboard** executes `demo.usp_PatientAccessDashboard` and records duration and logical reads.
- **Index Health** reads persisted live telemetry for the current NCI and provides playback controls for captured history.
- A background service pairs dashboard measurements with physical samples while compaction is running.
- The app does not create indexes, generate bloat, enable AIC, force plans, or load recorded calibration data.
- `/healthz` reports process health.
- `/readyz` reports whether Azure SQL is reachable through managed identity.

Set `ConnectionStrings__Caldova` for local development, then run:

```powershell
dotnet run --project ./CaldovaPatientAccessOps.csproj
```
