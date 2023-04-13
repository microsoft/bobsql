# Demo to see optimizations for Azure SQL Managed Instance

Once you have migrated you want to make sure you are optimizing your Azure SQL Managed Instance deployment through three examples:

- Azure Hybrid Benefit
- Start/Stop Instance
- Built-in High Availability

## Save costs with Azure Hybrid Benefit

1. Using the Azure Portal under Compute + Storage show the costs differences that are dynamically changed between **Pay-as-you-go** and **Azure Hybrid Benefit**.

## Stop/Stop Instance

You can stop an Azure SQL Managed Instance and save costs on compute and SQL licensing. In the Azure Portal you can select **Stop** at the top of the overview page to stop the instance at any time and select **Start** to restart it.

You can also create a schedule to stop and start the instance. On the left-hand menu in the Azure Portal for the Azure SQL Managed Instance, select **Start/Stop Schedule**. Then create a schedule (even per day) for when to stop and start again your instance.

## Built-in High Availability

Even though we did not setup a failover cluster, the General Purpose Service Tier has built-in high availability. Learn more at <https://learn.microsoft.com/azure/azure-sql/database/high-availability-sla>
