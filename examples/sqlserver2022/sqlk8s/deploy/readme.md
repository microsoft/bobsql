# Deploy SQL Server 2022 to Kubernetes

Inspect [step1_connectcluster.ps1](step1_connectcluster.ps1), then follow the
numbered steps through namespace/context selection, service and secret setup,
storage, deployment, logs/events, and SQL connectivity.

The manifests are [sql2022deployment.yaml](sql2022deployment.yaml),
[sqlloadbalancer.yaml](sqlloadbalancer.yaml), and [storage.yaml](storage.yaml).
Review image tags, resource requests, storage class, service exposure, and
privately supplied credentials before applying them.

Use a disposable cluster with `kubectl`, PowerShell, and the SQL client
referenced by [step12_querysql.ps1](step12_querysql.ps1). Confirm the active
cluster context and get approval before creating billable resources.

Once deployment is healthy, the [failure lab](../ha/readme.md) can reuse it.
Inspect [cleanup.ps1](cleanup.ps1) and persistent-storage impact before teardown.
