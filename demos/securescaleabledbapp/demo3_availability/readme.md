# Demo steps for Availability for Azure SQL Database

Here are steps to demonstrate bult-in retry logic for the SQL provider against an Azure SQL Database

## Prereqs

- VS 2022 Community Edition
- Nuget packages for Microsoft.Data.SqlClient and System.Configuration.Configuration Manager
- Use VS to Add a new item for an Application Configuration file
- Deploy two Azure SQL Databases (General Purpose service tier) and Server. You need two databases to show failover since you can only manually failover every 15 mins.
- Put both your database connection strings in the app config file.
- You will use the SQL admin login and password to authenticate
- Install Azure Powershell modules: https://docs.microsoft.com/en-us/powershell/azure
- Edit **failovergp1.ps1** and failover gp2.ps1 to point to your server, resource group, and each database.

##  Demo steps

1. Show the code on how retry logic works with the provider
1. Comment out the code to assign the retry provider to the connection
1. Assign your connection to the first Azure SQL Database in your code
1. Execute the program
1. Run **failovergp1.ps1** to initiate a GP service tier failover
1. Notice how errors (shown in red) appear until the failover is complete and app starts reconnecting
1. Change your connection to use the 2nd GP database
1. Uncomment the retry logic code and reubild the app
1. Execute the program
1. Run **failovergp2.ps1** to initiate a GP service tier failover
1. Note the yellow and grey text which are evidence of retry behind the scenes.
