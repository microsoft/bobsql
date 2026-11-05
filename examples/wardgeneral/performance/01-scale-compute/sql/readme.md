# Scale-compute workload SQL

Read and write statements used by the
[scale-compute walkthrough](../README.md): chart lookups, clinical notes, lab
results, medication orders, and vitals.

Use them through the parent orchestration so connection targets, workload
mix, duration, and scaling approval remain consistent. These are not independent
schema-creation scripts. They expect the existing Ward General database and
stored-procedure contracts.

Writes change synthetic lab data. Preserve parameterization and compare the
same workload across compute settings before drawing performance conclusions.
