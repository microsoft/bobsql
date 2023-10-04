# PowerApps and Azure SQL Database

These are the steps to create a PowerApp that connects to an Azure SQL Database based on a scenario of Orders in the sample AdventureWorkLT database.

## Pre-requisites

- You have an Azure SQL Database with the AdventureWorksLT sample database installed. You can use the free offer https://aka.ms/freedboffer to get started. To make the app simpler get admin access to the logical server for the database. It is not required but will make going through these steps simpler. 
- You will need the logical server, database name, and admin login and password.
- Ensure the Azure SQL Database is setup to support SQL Authentication and has Allow Azure Services to Access Server set to ON. You can find this setting in the Azure Portal under the SQL Database Server settings.
- You have access to an Power Platform environment to build a new Power App. You can use a Power Apps free trial at https://signup.microsoft.com/get-started/signup?products=83d3609a-14c1-4fc2-a18e-0f5ca7047e46&ali=1.

## Step 1: Create the app and add in the order list

1. Connect to Power Apps at https://powerapps.microsoft.com.
1. Let's add a connection to the database before creating the app. Select ...More on the left hand menu and select Connections.
    1. Click + New Connection at the top of the screen.
    1. Select SQL Server. You will now get a screen to put in your credentials to connect to Azure SQL.
    1. Using the drop down select SQL Server Authentication choose Connect directly (cloud services) and enter in the Server, Database, User Name and Password. Click Create.
1. Now let's create a blank Canvas app.
    1. On the left hand menu select **+ Create** and select **Blank App**
    1. Select option to Create a Blank Canvas app.
    1. Give the app a name, select the Tablet layout and click Create. You will now have a blank canvas to work with.
1. Now let's a list of orders in the canvas app using a table from the database.
1. Click the + icon on the left hand menu and under Layout select Blank Vertical Gallery. The gallery item will be placed on the canvas. In Select a data source type in sql and choose SQL Server.
1. Choose the connection you created earlier.
1. Under Choose a table check the SalesLT.SalesOrderHeader table and select Connect.
1. Let's now change some properties for the Gallery item.
    1. Under the Gallery item select the Layout tab and change the Layout to Title, subtitle, and body.
    1. Click on Edit next to Fields.
    1. The following fields should be selected:
        1. Title1 - SalesOrderID
        1. Subtitle1 - PurchaseOrderNumber
        1. Body1 - CustomerID
1. Now we want the CompanyName from the SalesLT.Customer table instead of CompanyID. We will use a lookup to get the CompanyName from the CustomerID but we need the SalesLT.Customer as a connection.
    1. On the top menu click **+ Add Data**. Type in SQL and select SQL Server.
    1. Click + Add a Connection. Select the connection you created earlier.
    1. Check the SalesLT.Customer table and click Connect.
    1. Click on the Body1 field
    1. In the formula bar change ThisItem.CustomerID to the following: `LookUp('SalesLT.Customer', CustomerID = ThisItem.CustomerID, CompanyName)`
    1. You should now the Company Names values appear in the list.
1. Select the Play button at the top menu and test out the order list. You should see a list of orders with the Company Name instead of the CustomerID.

## Step 2: Add in the order form

Now on the canvas let's add an edit form that will allow us to edit the order in the list showing different fields than in the order list. This will again be based on the SalesLT.SalesOrderHeader table. We need the form to change context as we select each order on the left from the list.



