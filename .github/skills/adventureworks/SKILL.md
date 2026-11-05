---
name: adventureworks
description: "Import or prepare the AdventureWorksLT2025 sample database using the bundled BACPAC. Use when working with examples/adventureworks, importing AdventureWorksLT into Azure SQL, or preparing sample data for SQL demos."
---

# AdventureWorksLT sample import

## Procedure

1. Read the [collection README](../../../examples/adventureworks/readme.md) and
   inspect [importadwlt.cmd](../../../examples/adventureworks/importadwlt.cmd).
   Confirm the user wants the LT sample, not the full AdventureWorks schema.
2. Verify SQLPackage is available, the target Azure SQL server/database exists,
   and the operator can authenticate with the script's Entra/MFA flow.
   Do not install tools or change authentication without approval.
3. Review the bundled BACPAC's provenance and the destination's current data.
   Confirm the target and import impact before executing; never overwrite a
   production database or place authentication material in the command file.
4. Adapt only the necessary target parameters and run the documented import.
   Capture failures explicitly. Evaluate documented compatibility warnings
   separately from an actual failed import.
5. Connect to the destination and verify expected `SalesLT` tables/data.
   Report the target and observed result, not just the process exit code.

## Boundaries

The package is sample data, not a backup/restore strategy or the full
AdventureWorks database required by every other collection. Do not delete the
destination as automatic cleanup. Follow [secret checks](../../../SECRET-SCANNING.md)
before publishing modified scripts or database packages.
