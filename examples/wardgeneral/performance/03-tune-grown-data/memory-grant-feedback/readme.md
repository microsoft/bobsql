# Memory-grant feedback tuning demo

Observe memory-grant feedback using the bounded workload described in the
[tuning overview](../README.md).

Start with [run-demo.ps1](run-demo.ps1) in preview mode. Check the target,
compatibility level, Query Store prerequisites, and data volume before using
the parent's `-Execute` flow. The sequence uses
[01-setup.sql](01-setup.sql), [02-run.sql](02-run.sql), and
[03-cleanup.sql](03-cleanup.sql).

Inspect repeated-execution plans and grants; do not infer feedback from a
single elapsed-time measurement. Run cleanup before repeating setup, and
remove only the demo-owned objects.
