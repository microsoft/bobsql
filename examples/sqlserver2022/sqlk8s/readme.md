# SQL Server 2022 on Kubernetes

This collection has two linked walkthroughs:

1. [deploy](deploy/readme.md): connect to a cluster, configure resources, deploy
   SQL Server, and verify connectivity.
2. [ha](ha/readme.md): observe restart and pod-failure behavior on that lab.

You need a disposable Kubernetes environment, `kubectl`, PowerShell, SQL
connectivity tools, suitable storage, and permission to create the resources.
Inspect manifests, namespaces, contexts, secrets, and service exposure first.

Pod restart/recreation is not the same as a SQL Server availability-group or
data-loss guarantee. Failure exercises are disruptive. Approve billable or
destructive steps and inspect cleanup scripts before removing resources.
