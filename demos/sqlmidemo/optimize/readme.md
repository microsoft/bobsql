## Demo to see optimizations for Azure SQL Managed Instance

Once you have migrated you want to make sure you are optimizing your Azure SQL Managed Instance deployment through three examples:

- Azure Hybrid Benefit
- Start/Stop Instance
- Built-in High Availability

## Prerequisites

1. In the VM or machine for the SQL Server 2019 installation, install the ostress tool from <https://aka.ms/ostress>.
1. Install the az CLI from <https://learn.microsoft.com/cli/azure/install-azure-cli-windows?tabs=azure-cli>.

## Look at optimization using the Azure Portal

1. Using the Azure Portal under Compute + Storage show the costs differences that are dynamically changed between **Pay-as-you-go** and **Azure Hybrid Benefit**.
1. Using the Azure Portal see how there is a method at the top of the portal page for the Managed Instance to Stop t. Stopping a Managed Instance will stop billing for compute and SQL licensing until it is restarted. On the left hand menu select Start/Stop schedule to show how you can create a schedule of when to stop and start the instance.

## Built-in High Availability

Even though we did not setup a failover cluster, the General Purpose Service Tier has built-in high availability. You can see this in action through the following steps in the VM or machine you are running SQL Server 2019 which has the ability to connect to Managed Instance. You will need two command windows to run this demo.

### Prepare

1. Edit the script **connectmi.cmd** for your Managed Instance name, sql admin, and password.
1. Edit the script **failover.cmd**. The -g parameter value is the resource group for the managed instance and the -n value is the managed instance name.

### Steps

1. Login to Azure using the **azlogin.cmd** script.
1. Execute the script **connectmi.cmd**. You should see a constant set of results for the query SELECT @@VERSION.
1. In another command window, execute the script **failover.cmd**.
1. After a few seconds, you should see errors in the window running connectmi.cmd. After no more than a few minutes it should automatically reconnect and run again.

    > **Note:** If you want to run this demo again, you can only manually failover every 15 minutes.
