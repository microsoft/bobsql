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

- Your Azure subscription must be enrolled in the November 2022 Feature Wave. Read more at <https://learn.microsoft.com/azure/azure-sql/managed-instance/november-2022-feature-wave-enroll>.

- Download SQL Server Management Studio (SSMS) from https://aka.ms/ssms19. For purposes of this example, run SSMS in the virtual machine where SQL Server is connected to Azure SQL Managed Instance.

## Setup

Follow the instructions at <https://github.com/microsoft/bobsql/blob/master/demos/sqlmidemo/setup/readme.md>.

## Perform an online migration from SQL Server 2019 to Azure SQL Managed Instance

Follow the steps in the **online_migration\readme.md** file to perform an online migration to Azure SQL Managed Instance.

## See the compatibility between SQL Server and Azure SQL Managed Instance.

Follow the steps in the **compat\readme.md** folder. You must have completed the online_migration steps prior to this set of examples.

## Optimize costs and do more with less using the cloud with Azure SQL Managed Instance.

Follow the steps in the **optimize\readme.md** folder. You must have completed the online_migration steps prior to this set of examples.

## Rapidly adapt to your business needs with Azure SQL Managed Instance.

Follow the steps in the **adapt\readme.md** folder. You must have completed the online_migration steps prior to this set of examples.

## Extend your investment with Azure SQL Managed Instance using new capabilities.

Follow the steps in the **extend\readme.md** folder. You must have completed the online_migration steps prior to this set of examples.