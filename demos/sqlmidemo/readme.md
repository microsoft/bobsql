# This is a demonstration of the fundamental capabilities of Azure SQL Managed Instance.

In this example you will learn how to:

1. Perform an **online migration** from SQL Server 2019 to Azure SQL Managed Instance
1. See the **compatibility** between SQL Server and Azure SQL Managed Instance.
1. **Optimize costs** and do more with less using the cloud with Azure SQL Managed Instance.
1. Rapidly **adapt to your business needs** with Azure SQL Managed Instance.
1. **Extend your investment** with Azure SQL Managed Instance using new capabilities.

## Prerequisites

- An Azure subscription with permissions to create an Azure SQL Managed Instance and an Azure Virtual Machine for SQL Server 2019.

> **Note:** You can use your own SQL Server 2019 instance but you will need to connect your instances with the virtual network of the Azure SQL Managed Instance. Your existing SQL Server 2019 instance must be using CU19 (EE and Dev editions) or CU17 (Standard Edition). In this example, we will attempt to migrate an existing SQL Server and have parity for resources. The Azure SQL Managed Instance deployed will use 8 vCores and 512Gb of storage. If your SQL Server 2019 database requires more CPUs or storage you may need to use higher options with your Azure SQL Managed Instance deployment. This example also assumes the SQL Server 2019 instance is a "stand-alone" instance or is part of a failover cluster. If you use an existing Availability Group, that is fully supported but this example first migrates SQL Server to a choice that does not have a built-in AG (but will extending to do that).

- Your Azure subscription must be enrolled in the November 2022 Feature Wave. Read more at <https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/november-2022-feature-wave-enroll>.

- Download SQL Server Management Studio (SSMS) from https://aka.ms/ssms19. For purposes of this example, run SSMS in the virtual machine where SQL Server is connected to Azure SQL Managed Instance.

## Setup

1. Create a new resource group in Azure in a region supported by the November 2022 Feature Wave. For this example, I used the East US region. For purposes of this example, my resource group is called bwmigratetosqlmirg.

### Deploy an Azure SQL Managed Instance

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

Wait for the Azure SQL Managed Instance to be created. Since this instance is part of the November 2022 Feature Wave, the deployment can be as fast as 30 minutes.

### Deploy a SQL Server 2019 instance with Azure Virtual Machine.

1. Create a new subnet in the virtual network for the deployed Azure SQL Managed Instance per these instructions. https://learn.microsoft.com/azure/azure-sql/managed-instance/connect-vm-instance-configure?view=azuresql. This is the subnet where the SQL Server 2019 Virtual Machine will be placed.
1. Now create a new SQL Server 2019 deployment in an Azure Virtual Machine.Use the marketplace to create a SQL Server 2019 Standard Edition on Windows Server 2022.

**Basics**

**Disks/Networking/Management/Monitoring/Advanced**

Use all the defaults

**SQL Server settings**

Use all defaults except for Storage to minimize costs for this example I configured data and log to be shared and only chose 512Gb P20 storage. I chose the option for tempdb to be on the local SSD (D: Drive).

Click **Review+Create** and then **Create** to create the virtual machine.

### Create a new database and table with data in SQL Server 2019

    1. Create a new database and table for SQL Server 2019 using the provided script **ddl.sql**.

## Perform an online migration from SQL Server 2019 to Azure SQL Managed Instance


## See the compatibility between SQL Server and Azure SQL Managed Instance.


## Optimize costs and do more with less using the cloud with Azure SQL Managed Instance.


## Rapidly adapt to your business needs with Azure SQL Managed Instance.


## Extend your investment with Azure SQL Managed Instance using new capabilities.