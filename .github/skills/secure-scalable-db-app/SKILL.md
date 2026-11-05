---
name: secure-scalable-db-app
description: "Guide Azure SQL application security, parameter-sensitive-plan performance, and SqlClient retry/failover demonstrations. Use when working with examples/securescaleabledbapp and its demo1_secure, demo2_perf, or demo3_availability walkthroughs."
---

# Secure, scalable, available Azure SQL application

## Procedure

1. Read the [collection overview](../../../examples/securescaleabledbapp/readme.md)
   and select security, performance, or availability.
2. Verify Azure SQL targets, identities, Visual Studio/.NET and SqlClient
   requirements. The collection supplies source/configuration snippets, not
   a complete solution/project; use the walkthrough's project setup.
3. Inspect App.config and scripts for endpoint/authentication assumptions.
   Keep credentials private. Confirm actual filenames before running inherited
   instructions; the bundled availability helpers include `failovergp1.ps1`
   and `failovergp3.ps1`, not every filename named in the old prose.
4. For security, use only an isolated, user-owned sample database. Inspect the
   intentionally unsafe query example and its parameterized alternative;
   never expose the unsafe path or test destructive input against real data.
5. For performance, follow the local
   [PSP walkthrough](../../../examples/sqlserver2022/IQP/pspopt/readme.md)
   after verifying feature/build requirements instead of relying on the
   inherited preview-era external link.
6. For availability, review retry configuration and observe a bounded probe.
   Obtain explicit approval before failover and verify the intended database
   and resource group. Distinguish observed retries/recovery from an SLA claim.
7. Restore the safe query path and close lab processes. Confirm scope before
   cleanup; do not delete shared cloud resources or weaken firewall rules.

Follow [secret checks](../../../SECRET-SCANNING.md) before publishing.
