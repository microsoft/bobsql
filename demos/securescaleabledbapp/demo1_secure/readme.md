# Azure SQL Database demos for security

The following are demos for showing fundamental security topics for Azure SQL Database

## Prereqs

- VS 2022 Community Edition
- Nuget packages for Microsoft.Data.SqlClient and System.Configuration.Configuration Manager
- Use VS to Add a new item for an Application Configuration file
- Deploy an Azure SQL Database and server. No specific service tier but be sure to not allow public access by default. You will need to enable AAD authentication for the server.
- You will need an AAD account to authenticate to login with the application.
- Install Azure Data Studio from https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio

## Security connectivity

1. Show the database in the Azure portal. Show the server name to connect to.
1. Bring up the SQLSecurity project in Visual Studio in our Azure VM running Windows 11.
1. Show the connection string to connect to the server. Go over pieces of the connection string.
1. Try to run the program and show the error we cannot connect
1. Go to the portal and use the Firewall and virtual networks setting to Allow Azure services. Talk about the various connectivity options including firewalls.
1. Run the program again and see it connect.
1. Show AAD auth in the portal for the server.

## SQL Injection

1. Review the results from the SQL notebook sqli.ipynb in Azure Data Studio
1. Uncomment the code to show how an injection works. Run the program and put in a valid SalesOrderNumber like SO71774
1. Show how the query is constructed in the code
1. Run the application again and put in this value

    `bob' or 1=1--`

1. Show the resulting query in the watch window
1. Run the code again but this time put in this value

    `bob'; drop table SalesLT.SalesOrderHeader2--`

1. Go back into ADS and see the table is gone
1. Run selinto.sql to recreate the table
1. Comment out the code that is bad and uncomment the code to use parameters. Show the code
1. Launch Profiler in ADS
1. Run the program and see the results. Show how sp_executesql is used and that the injected code is now part of the "string" for a SalesOrderNumber and why results are empty.
1. Finally go into the portal and see you have an injection alert detected by Microsoft Defender