# Kubernetes restart and failure lab

Continue from the [deployment walkthrough](../deploy/readme.md). The numbered
steps start with [step13_createdb.ps1](step13_createdb.ps1), inspect pods,
deliberately disrupt SQL Server or a pod, and query the database afterward.

Use the same disposable cluster context and deployed resources. Review
[step15_crashsql.ps1](step15_crashsql.ps1) and
[step18_podfailure.ps1](step18_podfailure.ps1) before execution and obtain
approval for disruption. Capture pod transitions, reconnect behavior, and
database results rather than assuming successful recovery.

These exercises show orchestration behavior, not a general SQL HA or RPO/RTO
guarantee. Read [cleanup.ps1](cleanup.ps1) and preserve any needed evidence
before deleting the lab.
