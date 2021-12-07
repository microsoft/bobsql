# Demos for Introduction to Azure Arc-enabled SQL Managed Instance

These are the basic instructions for doing demos for Azure Arc-enabled SQL Managed Instance.

## Pre-reqs

Deploy Azure Arc-enabled SQL Managed Instance on the k8s of your choice. For my demos, I used https://docs.microsoft.com/en-us/azure/azure-arc/data/create-sql-managed-instance but deployed in direct connected mode all using the portal and used AKS for my k8s platform.

## Explore Azure Arc-enabled SQL Managed Instance

Show deployed resources in the Azure portal
- Note the end point in the portal to connect to SQLMIAA
Use Azure SQL VM to show SSMS connections to primary.

- Object Explorer looks like SQL Server
- Show @@version
- Show user database already created

Show ADS connecting to the primary
- Explore the Controller dashboard and all the options including SQLMIAA config and backup/restore

- Show Grafana dashboard
- Show metrics in the portal for MI

Let’s look  at some k8s

- Show the arc agent pods from the namespace azure-arc
- Show the pods for the namespace arcdata
- Show all resources and point out the endpoints for the controller, SQLMIAA primary, and secondary replica

## Arc High-Availability

- Show in SSMS the AG dashboard
- Show database we created earlier in the secondary replica
- Create a new table and see it in both
- Kill the main pod and see how HA failover kicks in. Show in SSMS in Availability replicas how a different pod has taken over as primary but the connections to primary and secondary have not changed.
