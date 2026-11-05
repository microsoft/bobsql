# Advanced waits

Choose a workshop scenario:

- [preemptive](preemptive/readme.md): investigate a controlled preemptive-wait
  reproduction with SQL diagnostics and debugger support.
- [threadpool](threadpool/readme.md): observe worker pressure and waiting
  requests under a deliberate workload.

Read the selected scenario's README and scripts first. Both require the
isolated lab and tooling described in the [workshop overview](../readme.md).
Review instance-wide worker settings, target databases, and workload limits.
Prepare a separate diagnostic/DAC session before generating worker pressure.

Obtain approval for disruptive changes. Stop the specific lab processes,
close transactions, restore original settings, and follow scenario cleanup.
Do not infer a production diagnosis from wait names alone.
