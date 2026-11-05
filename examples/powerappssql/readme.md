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

1. On the top right we will want an edit form of each order in the list. So when we click on a given order in the list a form appears shows more information of that order which we can view or edit
1. Click on Insert in the top Menu and choose Edit Form. Move the form over to the right

We need to add the data source. In this case it is the same data source for the SalesOrderHeader table.

3. On the right hand side for Properties, select the Data Source drop-down. Choose the SalesOrderHeader  table.
4. We need some fields to populate. To get this going quickly, choose these fields
	1. On the Properties pane select Edit Fields
    2. Choose these fields by clicking on them
        
        AccountNumber<br>
        DueDate<br>
        OnlineOrderFlag<br>
        ShipMethod<br>
        Status<br>
        TotalDue<br>

5. We would like as we select any order to the left to appear in the form so to do that we can click on Advanced and under Data fill out the following in the Item field: Gallery1.Selected
6. Click on the time fields and make them not visible
7. Let's test what we have by hitting the Play button. 
1. You should be able to select an order item and see the fields change context
1. Let's Save at this point so we don't lose our work.

## Step 3: Add in the order details

Now let's add in the order details for the order. This will be based on the SalesLT.SalesOrderDetail table. We will add a new gallery on the canvas to display this. When a user clicks on an order in the list, this new order details list should switch context for that order. In addition, we will want to show the name of the Product instead of the ProductID.

1. Select Insert for a blank vertical gallery. Position this over the blank space under the edit form. Change layout to title, subtitle, and body
1. On the right side select the Drop Down for Data Source. 
1. We need a different table so type in SQL in the search. Select SQL Server
1. Choose the SalesLT.SalesOrderDetail table and select Connect
1. Choose these fields

	ProductID<br>
	Modified Date<br>
	OrderQty<br>

1. Now we need to tie in the Order vertical list on the left with this list in middle. There is a relationship between these and we can use the Filter formula to help.
1. Select the new vertical gallery item. At the top of the Formula edit box type in this formula `Filter('SalesLT.SalesOrderDetail', SalesOrderID = LookUp('SalesLT.SalesOrderHeader', SalesOrderID = Gallery1.Selected.SalesOrderID, SalesOrderID))`
1. And we want ProductName not just the ID. Add a new connection for the SalesLT.Product table like you did earlier for the SalesLT.Customer table.
1. Then click on the ProductID field and put this in the formula `LookUp('SalesLT.Product', ProductID = ThisItem.ProductID, Name)`
1. Let's test the app again by hitting the Play button
1. As you select the Orders to the left you should now see the Edit form context change and the list of Order Details change
1. Save your work.

## Step 4: Finish the app

Let's finish the app by sorting the order list and adding a button to allow the user to save changes in the edit form.

1. Click on Gallery1 and put in this formula Sort('SalesLT.SalesOrderHeader', SalesOrderID).
2. Let's add a button to allow the user to save updates to the order form.
3. Go to Screen1 on the Tree View
4. Insert..Icon..Check
5. Move Check to far right side of the canvas.
6. Select the check icon. On Advanced, Action, OnSelect, type in SubmitForm( Form2 ). So now changes to data in the form will be updated in the database.
7. Select DisplayMode and put in this formula: If( Form2.Unsaved, Edit, Disable
8. Save your work. Then play the app.
9. The order list should now be sorted by SalesOrderID.
10. Notice the check icon is greyed out because no changes have been made.
11. Take the first order and select the Online Order so it is ON. Notice the check icon is now active. Click the check icon to save the change. You can use any SQL tool to verify that change was made.
12. Optionally, select each gallery and form and add a color to it.
13. Save your work and play the app to see it all in action.