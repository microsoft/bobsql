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

Azure SQL Managed Instance allows you to easily scale or change the configuration of your compute and storage resources.

1. Using the Azure Portal select Compute+Storage in the left-hand menu of the Azure SQL Managed Instance.

1. You now have choices to change the service tier, zone redundancy, hardware choices, number of cores, max size of storage, and backup redundancy choices. All of these choices are *online* since you do not have to perform any migration tasks. A change for these may require the application to reconnect to the instance at the end of the operation.

## Auto-failover groups to extend redundancy and read-scale

1. Follow the tutorial in the documentation to perform the prerequisites and steps to configure and add a managed instance to an auto failover group: <https://learn.microsoft.com/azure/azure-sql/managed-instance/failover-group-add-instance-tutorial>

1. Once you have configured you auto failover group, you can go to the primary Azure SQL Managed Instance in the Azure Portal and select Failover Groups from the left-hand menu. You can view the configured failover group settings, edit the configuration, or manually force a failover.

2. These settings show the endpoints to connect to the primary for read/write and optionally connect to the secondary for read scale. These endpoints don't change no matter which instance is the primary or secondary.
