# Live Demo Runbook

## Invariants

- Use one unchanged procedure: `demo.usp_PatientAccessDashboard`.
- The qualifying NCI must be created by Azure SQL and report `auto_created = 1`.
- Do not force plans or add query hints.
- Do not drop or recreate the auto-created NCI after detection.
- Bloat and AIC eligibility use temporary insert/delete rows only.
- Capture page count and density with `DETAILED` physical stats, paired to the
	latest dashboard duration and logical reads.

## 1. No Nonclustered Index

Run `deploy/02-initialize-database.ps1` only when a fresh environment is intended.
It recreates the isolated demo schema and loads two million rows.

Confirm that `demo.PatientAccessActivity` has only `PK_PatientAccessActivity`, then open the app and click **Refresh dashboard**. Index Health should report `Missing Index` after telemetry is captured.

## 2. Automatic Tuning Creates the Index

Run one 15-minute workload interval:

```powershell
./deploy/05-run-workload.ps1
```

After each interval, show the current recommendation and check for the automatic index:

```powershell
./deploy/06-show-index-recommendation.ps1
./deploy/07-check-auto-index.ps1
```

If the check reports that no qualifying auto-created index exists, run another
15-minute interval and check again. Repeat for several hours as needed. Continue only
after the check succeeds. The index must report `auto_created = 1` and cover:

- Keys: `ServiceRegionId`, `ActivityAt`
- Includes: `AppointmentStatus`, `SpecialtyCode`, `WaitMinutes`, `PatientInstructions`, `RevisionNumber`

Refresh the dashboard and open Index Health to capture the healthy indexed state.

## 3. Create Real Bloat

```powershell
./deploy/08-create-bloat.ps1
```

The script inserts and deletes bounded temporary rows with wider included values. It returns the base table to exactly two million rows and never updates surviving rows.

The validated sequence uses four cumulative steps: 200,000 rows at 220 bytes,
500,000 rows at 1,000 bytes, 300,000 rows at 2,000 bytes, and 500,000 rows at
2,000 bytes.

Refresh the dashboard, then run `deploy/10-check-progress.ps1` to pair the slower query measurement with the sparse NCI state.

## 4. Enable Automatic Index Compaction

```powershell
./deploy/09-enable-compaction.ps1
```

This enables AIC, marks the phase `Compaction Running`, and performs three bounded insert/delete eligibility cycles. It does not update surviving rows.

Each validated eligibility cycle inserts and deletes 200,000 temporary rows with
a 220-byte included value.

While AIC is running:

1. Refresh the dashboard.
2. Run `deploy/10-check-progress.ps1`.
3. Repeat until Index Health shows materially fewer pages, higher density, and recovered query performance.

The telemetry procedure marks `Compaction Complete` when the NCI has fallen below 20% of its bloated page count, density is at least 60%, and the latest dashboard measurement is under one second.

## Presentation Message

> Automatic tuning created the right access path. Normal data churn left that index sparse. Automatic Index Compaction restored its efficiency in the background without dropping or rebuilding the index.
