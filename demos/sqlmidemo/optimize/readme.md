# Demo to see optimizations for Azure SQL Managed Instance

Once you have migrated you want to make sure you are optimizing your Azure SQL Managed Instance deployment through three examples:

- Azure Hybrid Benefit
- Start/Stop Instance
- Built-in High Availability

## Look at optimization using the Azure Portal

1. Using the Azure Portal under Compute + Storage show the costs differences that are dynamically changed between **Pay-as-you-go** and **Azure Hybrid Benefit**.

1. Using the Azure Portal see how there is a method at the top of the portal page for the Managed Instance to Stop t. Stopping a Managed Instance will stop billing for compute and SQL licensing until it is restarted. On the left hand menu select Start/Stop schedule to show how you can create a schedule of when to stop and start the instance.

## Built-in High Availability

Even though we did not setup a failover cluster, the General Purpose Service Tier has built-in high availability. See a visual for how this works in the slides of the demo at XXXXXX.
