# This is a demonstration of the fundamental capabilities of Azure Arc-enabled SQL Managed Instance.

In this example you will learn how to:

1. Learn now to **deploy and migrate** from SQL Server 2019 to Azure SQL Managed Instance.
1. See the **compatibility** between SQL Server and Azure-Arc enabled SQL Managed Instance.
1. **Optimize costs** and do more with less using the cloud experience of Azure Arc-enabled SQL Managed Instance.
1. Rapidly **adapt to your business needs** with Azure Arc-enabled SQL Managed Instance.
1. **Extend your investment** with Azure Arc-enabled SQL Managed Instance using new capabilities.

## Prerequisites

> **Note:** There are methods to quickly deploy all the components for Azure Arc-enabled SQL Managed Instance through the Azure Arc Jumpstart program. See more information at <https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_data/>.

This demonstration will use the following components:

- Azure Kubernetes Service (AKS) running in Azure. But you can use any k8s cluster type listed at <https://learn.microsoft.com/azure/azure-arc/data/plan-azure-arc-data-services#deployment-requirements>. Your k8s cluster must be capable of connecting to Azure.

- Azure Arc-enabled SQL Managed Instance hosted on the AKS cluster.

- A client virtual machine to run tools and connect to AKS and the Managed Instance. This demonstration uses a Windows Server client but except for demos using SQL Server Management Studio, you can use any OS VM or client machine.

- Download SQL Server Management Studio (SSMS) from <https://aka.ms/ssms19> to run in your client machine. There are a few exercises in the demo that use SSMS but you are not required to use SSMS for all exercises. SSMS is used more to show compatibility with SQL Server.

- Download Azure Data Studio (ADS) from <https://aka.ms/azuredatastudio> to run in your client machine. ADS is supported on Windows, Linux, or MacOS.

The rest of the prerequisites are covered in the Setup section.

## Setup

Follow the instructions at <https://github.com/microsoft/bobsql/blob/master/demos/arcsqlmidemo/setup/readme.md>.

## Deploy an Azure-Arc enabled SQL Managed instance and migrate an existing SQL Server Database.

Follow the steps in the **deploy_and_migrate\readme.md** file to perform an online migration to Azure SQL Managed Instance.

## See the compatibility between SQL Server and Azure Arc-enabled SQL Managed Instance.

Follow the steps in the **compat\readme.md** folder. You must have completed the deploy_and_migrate steps prior to this set of examples.

## Optimize costs and do more with less using the cloud with Azure SQL Managed Instance.

Follow the steps in the **optimize\readme.md** folder. You must have completed the online_migration steps prior to this set of examples.

## Rapidly adapt to your business needs with Azure SQL Managed Instance.

Follow the steps in the **adapt\readme.md** folder. You must have completed the online_migration steps prior to this set of examples.

## Extend your investment with Azure SQL Managed Instance using new capabilities.

Follow the steps in the **extend\readme.md** folder. You must have completed the online_migration steps prior to this set of examples.