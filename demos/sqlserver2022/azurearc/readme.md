# SQL Server Extension for Azure

The following are scripts you can use to setup the prereqs so you can use the SQL Server Extension for Azure feature in SQL Server 2022 setup.

You will need to use the az CLI or Azure Cloud Shell to execute these scripts. You wil also need to create a resource group in a supported region for SQL Server on Azure Arc-enabled servers.

**sqlazureext.json**

This is a JSON file to define the required permissions for a custom role

**createcustomrole.ps1**

An example using az CLI to create a custom role with all the needed permissions to install the SQL Server Extension for Azure during SQL Server 2022 setup.

**sqlazureext.ps1**

An example using az CLI to create a service principal at a resource group level assigning it the custom role you created