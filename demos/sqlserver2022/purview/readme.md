# Exercise for Microsoft Purview access policies for SQL Server 2022

Exercise for Microsoft Purview access policies for SQL Server 2022

## Prereqs

- A virtual machine or computer with at least 2 CPUs and 8Gb RAM and be connected to Azure over the internet or proxy. This exercise currently does not support Azure Virtual Machine.
- SQL Server 2022 Evaluation Edition registered with Azure as an Azure Arc-enabled SQL Server.
- You have enabled Azure Active Directory (AAD) authentication for SQL Server 2022.
- An Azure subscription with permissions to create a Microsoft Purview account.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.

## Setup Microsoft Purview access policies

1. Create a Microsoft Purview account.
1. Setup permissions with Purview to allow you to create, publish policies, and enable DUM. Please follow the steps in this documentation carefully to setup these permissions: https://docs.microsoft.com/azure/purview/how-to-policies-data-owner-arc-sql-server#conf
1. Register your Purview account with the Azure extension for SQL Server through the Azure portal. 
    1. Find your SQL Server – Azure Arc resource that you created for AAD Authentication in the Azure portal. Select on the left-hand menu Azure Active Directory.
    1. Select enable and fill out the Microsoft Purview Endpoint by putting in your Purview account name.
    1. Select Save at the top of the screen. When the progress message disappears the registration is complete.

## Using Microsoft Purview access policies

1. Choose two AAD accounts in your organization. One will be for performance monitoring and one for data reading.
1. Launch the Purview Governance Portal from the Azure Portal (also known a Purview Studio).

### Create a data access policy for reading

1. Use the Data Map menu option to register your Azure Arc-enabled SQL Server. Select Enable Data Use Management. The Application ID should be filled in automatically. If not select Refresh. Select Register.
1. Under the Data Policy menu option select Data policies.
    1. Select + New Policy and then Access Control
    1. Type in a name and select + New Policy Statement
    1. Now make the following choices:
        1. For effect choose Allow
        1. For action choose Read
        1. For data resources on the new screen choose Data Source type and then choose SQL Server on Azure Arc-enabled servers. Select Continue. Choose your server under Data Source Name and select Add.
        1. For subjects type in the AAD account you want to give read access to in the Select subjects search window and then select Ok.
    1. Select Save to create the policy.
    1. Select your policy and select Publish on the right side of the screen. Choose your data source and select Publish at the bottom of the new screen. You should now see a Published On date and time on the screen for your policy.
1. Execute the script**howboutthemcowboys.sql** against your SQL Server 2022 instance as your default sysadmin.
1. Execute the script **policyrefresh.sql** against your SQL Server 2022 instance as your default sysadmin..
1. Login into SSMS with the AAD account you created for the policy.
1. Execute the script **querythecowboys.sql** as the new AAD account. You should get back results.
1. Execute the script **dropthecowboys.sql**. You should get an error you don't have permissions which proves you can only read data.
1. Login to SSMS as a local administrator. Execute the script **policydmvs.sql** and **policyprincipals.sql** to view policy metadata.
1. Under the Data Policy menu option select Data policies.

### Creating a DevOps policy for performance monitoring

1. Under the Data Policy menu option select Data policies.
    1. Select + New Policy
    1. For Data source type choose SQL Server on Arc-enabled Servers and pick your registered SQL Server and select Select.
    1. Now choose Add/Remove subjects and pick a different AAD account then you used in the previous section.
    1. Select Save. No publish is needed.
1. Execute the script **policyrefresh.sql** against your SQL Server 2022 instance as your default sysadmin..
1. Execute the scripts **policydmvs.sql** and **policyprincipals.sql** as a sysadmin to see new metadata for the new account.
1. Login into SSMS with the AAD account you created for the policy.
1. Execute the script **perfdmvs.sql**. You should get results.
1. Execute the script querythecowboys.sql. You should get an error indicating you don't have access to read user data.
1. Execute the script**sp_configure.sql**. You should get an error to show you do not have sysadmin rights.

**Note**: As an optional step you could delete either of the polices in Purview, execute **polishrefresh.sql**, and then show you cannot login as the AAD account from the deleted policy.