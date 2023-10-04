# PowerApps and Azure SQL Database

These are the steps to create a PowerApp that connects to an Azure SQL Database based on a scenario of Orders in the sample AdventureWorkLT database.

## Pre-requisites

- You have an Azure SQL Database with the AdventureWorksLT sample database installed. You can use the free offer https://aka.ms/freedboffer to get started. To make the app simpler get admin access to the logical server for the database. It is not required but will make going through these steps simpler. 
- You will need the logical server, database name, and admin login and password.
- Ensure the Azure SQL Database is setup to support SQL Authentication and has Allow Azure Services to Access Server set to ON. You can find this setting in the Azure Portal under the SQL Database Server settings.
- You have access to an Power Platform environment to build a new Power App. You can use a Power Apps free trial at https://signup.microsoft.com/get-started/signup?products=83d3609a-14c1-4fc2-a18e-0f5ca7047e46&ali=1.

## Step 1: Create the app and add in the order list

1. Connect to Power Apps at https://powerapps.microsoft.com.
1. On the left hand menu select **+ Create** and select **Blank App**
1. Select option to Create a Blank Canvas app.
1. Give the app a name, select the Tablet layout and click Create. You will now have a blank canvas to work with.
1. Click on the Data icon on the left hand menu and click on Add Data.
1. In the Select a Data Source type in SQL and select SQL Server.
1. Click on + Add a connection. You will now get a screen to put in your credentials to connect to Azure SQL.
1. Using the drop down select SQL Server Authentication choose Connect directly (cloud services) and enter in the Server, Database, User Name and Password. Click Connect.
1. Click the + icon on the left hand menu and under Layout select Blank Vertical Gallery. The gallery item will be placed on the canvas..

