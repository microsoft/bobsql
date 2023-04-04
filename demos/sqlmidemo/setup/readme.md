## Setup for the Azure SQL Managed Instance demo

The following are setup steps required for the Azure SQL Managed Instance demo.

## Create a resource group in Azure

1. Create a new resource group in Azure in a region supported by the November 2022 Feature Wave. For this example, I used the East US region. For purposes of this example, my resource group is called bwmigratetosqlmirg.

## Deploy an Azure SQL Managed Instance

1.  Deploy an Azure SQL Managed Instance using the following choices during deployment:

**Basics**

- Use the resource group you specified in the previous step
- Specify a managed instance name. For purposes of this example, my instance name is bwsqlmi.
- Choose the following compute+storage choices:
    - Service Tier: General Purpose
    - Zone redundancy: No
    - Hardware generation: Standard-series
    - vCores: 8
    - Storage in GB: 512
    - SQL Server License: Azure Hybrid Benefit
    - Backup storage redundancy: Geo-redundant backup storage
- Authentication method: Use SQL authentication. Put in your SQL login and password which becomes the default sysadmin principal in the instance.

**Networking**

Use all defaults. By default a new virtual network will be created.

**Security**

Enable Microsoft Defender but leave all other choices as defaults

**Additional Settings**

Use all defaults

Now select **Review+Create** and then **select Create**.

Wait for the Azure SQL Managed Instance to be created. Since this instance is part of the November 2022 Feature Wave, the deployment can be as fast as 30-45 minutes.

## Deploy a SQL Server 2019 instance with Azure Virtual Machine.

1. Create a new subnet in the virtual network for the deployed Azure SQL Managed Instance per these instructions. <https://learn.microsoft.com/azure/azure-sql/managed-instance/connect-vm-instance-configure?view=azuresql>. This is the subnet where the SQL Server 2019 Virtual Machine will be placed.
1. Now create a new SQL Server 2019 deployment in an Azure Virtual Machine.Use the marketplace to create a SQL Server 2019 Standard Edition on Windows Server 2022.

**Basics**

- Use the resource group from the Azure SQL Managed Instance deployment
- Put in a virtual machine name. I used bwsql2019vm.
- Keep region the same as for the resource group and Azure SQL Managed Instance.
- For Availability Options choose "No infrastructure redundancy required"
- For Security type choose Standard
- For Image choose SQL Server 2019 Standard on Windows Server 2022 - x64 Gen2
- For size to reduce costs I chose Standard_D8s_v3 which provides 8 vCores and 32GB RAM.
- Supply a Window admin and password. You will use this to login to the Windows Virtual Machine.
- For inbound port rules choose the option which matches the security compliance of your organization. Since this is just an example, I use the default of leaving RDP port 3389 allowed. A more secure solution would not to allow 3389 and use Bastion or a virtual network.
- For Licensing you can choose Azure Hybrid Benefit if you have existing Windows licenses.

**Disks**

Use all the defaults

**Networking**

The portal should fill in the name of the virtual network for Azure SQL Managed Instance and the subnet you created earlier. Leave all other values to defaults.

**Management/Monitoring/Advanced**

Use all the defaults

**SQL Server settings**

Use all defaults except for Storage to minimize costs for this example I configured data and log to be shared and only chose 512Gb P20 storage. I chose the option for tempdb to be on the local SSD (D: Drive). Leave all other SQL options to their defaults.

Click **Review+Create** and then **Create** to create the virtual machine. The average deployment time for a SQL Server marketplace image like this can be as fast as 5 minutes.

## Create a new database and table with data in SQL Server 2019

1. Connect to the SQL Server 2019 instance.
1. Create a new database and table for SQL Server 2019 using the provided script **ddl.sql**.