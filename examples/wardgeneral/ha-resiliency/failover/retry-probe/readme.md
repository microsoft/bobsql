# Failover retry probe

[Program.cs](Program.cs) is a small .NET console probe that reuses the Ward
General data project's retry policy. Follow the
[failover walkthrough](../README.md) for orchestration and approval gates.

Its arguments are server, database, optional interval in milliseconds, and
optional duration in seconds. It uses encrypted Entra authentication and
repeatedly measures a small SQL request, reporting retries and failures.

Use the parent runner rather than assuming the probe itself triggers a failover.
It observes connectivity; a successful run is not an SLA guarantee. Check the
target, obtain approval before the separate failover operation, and stop the
probe when the observation window is complete.
