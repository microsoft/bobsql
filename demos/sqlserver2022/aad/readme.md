# Exercise for Azure Active Directory (AAD) authentication for SQL Server 2022

Exercise for Azure Active Directory Authentication (AAD) for SQL Server 2022

## Prereqs

- A virtual machine or computer with at least 2 CPUs and 8Gb RAM and be connected to Azure over the internet or proxy. This exercise currently does not support Azure Virtual Machine.
- SQL Server 2022 Evaluation Edition registered with Azure as an Azure Arc-enabled SQL Server.
- An Azure subscription using an Azure Active Directory (AAD) account in your organization you have deemed to be the **AAD admin** for SQL Server. This account should have the following permissions:
    - Member of the Azure Connected Machine Onboarding group or Contributor role in the resource group associated with the Azure extension for SQL Server.
    - Member of the Azure Connected Machine Resource Administrator role in the resource group associated with the Azure extension for SQL Server.
    - Member of the Reader role in the resource group associated with the Azure extension for SQL Server.
    - Permissions to create an Azure Key Vault.
    - **IMPORTANT**: You will need to be able to grant Admin consent for an Azure application. In order to grant Admin consent your AAD account must be a member of the Azure AD Global Administrator or Privilege Role Administrator. It is possible in your organization you don’t have this permission so either you will need to be granted this permission or have another AAD administrator configure this. Do not move forward until you have this permission resolved. If you don't have this permission you can setup AAD for SQL Server and your AAD admin will have access. But you will not be able to create any other AAD logins or users.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.

# Setup AAD with SQL Server 2022

1. Create an Azure Key Vault.
    1. Add your AAD admin account in the Contributor role for the key vault you created
    1. Setup access for the SQL Server 2022 instance to the Azure Key Vault. Use the Access Policies option on the resource menu for the key vault. Select Add Access Policy. Keep 0 selected for Key permissions. Add the Get and List permissions for Secret and Certificate. Then for Select principal use the name of the host of your SQL Server (the name of the Azure Arc SQL Server).
    1. Now grant access to the Azure Key Vault to the AAD account you would like to make the AAD admin for SQL Server. This is a similar process to the step above except for Key permissions you need Get, List, and Create. You also need Get, List, Set for Secret and Get, List, and Create for Certificate. It is possible you don’t need this step if you used the AAD admin account to create the Azure Key Vault.
1. Setup the AAD admin for SQL Server using the Azure portal.
    1. Find your SQL Server Azure Arc resource in the Azure portal.
    1. On the resource menu for this resource under Settings choose Azure Active Directory. Now choose Set Admin. Pick the AAD account you have selected as your AAD admin. You now will fill out information on a screen to set the admin:
    
    - Choose Service-managed cert.
    - Change your key vault to the Azure Key Vault you have created.
    - Choose service-managed app registration.
    - Leave the option for Purview disabled.
    
    c. Select **Save**. After a few minutes is successful your screen should display all the details including an Azure application ID.
1.  Grant consent to the Azure Application
    1. Find the Azure Application ID created from your Azure Active Directory in the portal under **App registrations**. The ID should be your SQL Server registered `<server name>`-MSSQLSERVER`<nnnn>`.
    1. Select **API permissions** from the left-hand menu and then select **Grant admin consent**.If this option is greyed out you don't have Global Administrator or Privileged Role Administrator rights for our AAD.

## Using AAD with SQL Server

1. On your local SQL Server execute the script **findaadlogin.sql** logged in as the local administrator account to see your new AAD admin account created as a login.
1. Login to SSMS using the option for Azure Active Directory and your AAD Admin login. Use MFA if your AAD supports it or you can just use password.
1. Add another AAD account as a login with sysadmin rights. Edit the script **createaadlogin.sql** with an account in your AAD and execute the script.
1. Login to SSMS with this new AAD account to verify the login works and has sysadmin rights.
1. Add another AAD account as a user in a database without creating a login by editing and executing the script **createaaduser.sql**.
1. Login to SSMS with this new AAD account to verify the login works. You must use the option in SSMS to specify the database name from the script to connect since the account was directly added to the database.
1. If you create an AAD group you can optionally give rights to the AAD group directly which allows all AAD accounts in the group to have login rights and permissions granted to the group. You can see an example of this syntax with **createaadgrouplogin.sql**.