# Demo to see how Azure SQL Managed Instance can help you rapidly adjust to your business

Azure SQL Managed Instance can help you rapidly adjust to the needs of your business. You can see this through the following examples:

- Maintenance windows and advanced notifications
- Simple Point-tn-Time-Restore (PITR) and long-term backup retention
- Simple scale of resources, hardware, or upgrade of service tiers.
- Auto-failover groups to extend redundancy or read-scale.

## Maintenance Windows and Advance Notifications

1. In the Azure Portal select Maintenance on left-hand menu. Then look at the drop-down choices for Maintenance Window.
1. Use the following documentation page to configure an Advanced Notification for planned maintenance: <https://learn.microsoft.com/azure/azure-sql/database/advance-notifications?view=azuresql#configure-an-advance-notification>

## Point-in-time Restore (PITR) and long-term backup retention

1. In the Azure portal select Backups from the left-hand menu. You can see for each database the earliest PITR as well as an easy option to perform a PITR.

2. You can select Deleted to easily restore databases you might have accidentally deleted.

3. You can select Retention Policies to setup long-term retention up to 10 years.

## Simple scale of resources, hardware, or service-tier upgrade



## Auto-failover groups to extend redundancy and read-scale

1. Follow the tutorial in the documentation to perform the prerequisites and steps to configure and add a managed instance to an auto failover group: <https://learn.microsoft.com/azure/azure-sql/managed-instance/failover-group-add-instance-tutorial>

2. 
