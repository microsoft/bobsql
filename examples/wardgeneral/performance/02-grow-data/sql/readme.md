# Data-growth workload SQL

Batch insertion statements for clinical notes, lab results, and observations,
used by the [data-growth walkthrough](../README.md).

Run through the parent orchestration against the existing synthetic Ward
General database. Review batch sizes, concurrency, duration, and storage cost
before execution. These statements deliberately increase data volume and log
activity; they are not read-only diagnostics.

Measure growth using the parent's verification steps and do not remove shared
application data as an ad-hoc cleanup shortcut.
