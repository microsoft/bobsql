---
name: auto-index-compaction
description: "Demonstrate automatic index compaction in Azure SQL Hyperscale. Use when working with examples/auto_index_compaction, page density after scatter deletes, AIC background cleanup, or scan IO comparisons."
---

# Automatic index compaction

## Procedure

1. Read the [walkthrough](../../../examples/auto_index_compaction/readme.md)
   and the numbered scripts. Verify the target is an Azure SQL Hyperscale lab
   with the required feature available; do not assume other service tiers work.
2. Confirm database identity, permissions, available space, and approval for
   data creation/deletion, configuration changes, and cold-cache measurement.
   Capture the starting configuration before modifying it.
3. Run setup and record baseline row count, density, pages, logical reads, and
   scan timing using the supplied measurement script.
4. Review the timing warning before degrading data. Enable AIC immediately
   after the DML workload as documented, without an unplanned pause that lets
   version cleanup finish first. Do not promise compaction on a fixed timer.
5. Monitor progress and version-store observations, then repeat the same scan
   measurement. Distinguish observed results from the README's example numbers.
6. With approval, follow the cleanup script and verify the lab table/configuration
   state. Do not disable a pre-existing setting without reviewing its ownership.

## Evidence

Compare the same workload and cache conditions. Explain unsuccessful
observations in terms of actual feature/timing evidence rather than inventing
a speedup. Use [secret checks](../../../SECRET-SCANNING.md) before publishing.
