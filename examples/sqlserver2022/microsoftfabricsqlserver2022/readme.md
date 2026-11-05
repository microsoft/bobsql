# Integrating SQL Server 2022 and the Microsoft Fabric.

In this example you will learn how to:

- Archive "cold" data for sales to a data lake using data virtualization capabilities in SQL Server 2022 to Azure Storage.
- Learn how to query archived data in Azure Storage just like it was a SQL Server table.
- How to integrate the archived sales data into a Microsoft Fabric Lakehouse.
- How to analyze trends for sales with customer sentiment using Microsoft Fabric Lakehouse data and PowerBI visualization.

> **Note:** You should be able to also demonstrate this example using Azure SQL Managed Instance since it also has the same data virtualization capabilities as used in this example as SQL Server 2022.

## Prerequisites

- You have installed SQL Server 2022 and enabled the PolyBase Query Service for External Data Feature during setup.
- Download SQL Server Management Studio (SSMS) from <https://aka.ms/ssms19> to run in your client machine.
- You access to a Premium PowerBI workspace to use the Microsoft Fabric.
- You have installed the OneLake File Explorer add-on for Windows.

## Archive and access data with SQL Server 2022 and data virtualization.

Follow the instructions in the **archivetodatalake/readme.md** file to setup, archive, and access data with data virtualization in SQL Server 2022.

## Create a shortcut for archived data from Azure Storage

1. Create a new Lakehouse in your Microsoft Fabric workspace
1. In the Lakehouse explorer create a new Shortcut under Files.
1. Select Azure Data Lake Storage Gen 2 as the External Source.
1. Use the dfs Primary Endpoint for the ADLS storage account (you can find this under the JSON view of the storage account.) For example, from the archivedatalake demo my dfs endpoint is https://bwdatalakestorage.dfs.core.windows.net. Put in the full SAS token from the storage account under Connection Credentials.
1. Provide the shortcut a name.
1. For subpath put in the Container Name
1. Use the Lakehouse Explorer to drill and verify the parquet file can be seen.

## Verify the data using a Notebook in Lakehouse Explorer

Use a Notebook in the Lakehouse Explorer to verify the archived sales data.

1. Select Open notebook/New notebook
1. Paste in the following PySpark code to query the data in the first cell.

```python
df = spark.read.parquet("<file path>")
display(df)
```

1. In the Lakehouse explorer select "..." from the parquet file and select **Copy relative path for Spark**
1. Paste in the copied path into `"<file path>"` (leave the quotes)
1. Select **Run all** at the top of the screen.
1. After a few seconds the results of your data should appear. YOu can now verify this is valid sales data.
1. Select Stop Session at the top of the menu.
1. You can optionally select the Save button to save the Notebook.

## Load the archived sales data as a table in the Lakehouse

1. Select the Lakehouse you created on the left hand menu to go back to the full Lakehouse explorer view.
1. Drill into the shortcut from Files and select "..." next to the parquet file. Select **Load to Delta table**. Put in a table name of salessept2022. You will see a Loading table in progress message. This will take a few seconds until it says Table successfully loaded.
1. In the Lakehouse explorer under Tables you will see the new table. If you click on the table you will see the sales data.

## Upload customer sentiment data into the Microsoft Fabric Lakehouse

1. Using the OneLake File Explorer add-on, copy the provided customersentimentsept2022.csv file into the your `<Lakehouse name>`.Lakehouse\Files folder.
1. In the Lakehouse Explore you should be able to click on Files and see the .csv now exists.
1. Select the "..." next to the file name and select Load to Delta table. Use the default name provided. You should get a **Loading table in progress** message and eventually a Table successfully loaded message.
1. You can now see the new table in the Tables view in Lakehouse Explorer. If you click the table you will table you will see the data in a table format.

## Create a relationship between the data

1. Let's make sure the two tables are known to have a relationship based on the customer column.
1. At the top right corner of the Lakehouse Explorer screen select the Lakehouse dropdown and select SQL Endpoint.
1. At the bottom of the screen select Model.
1. You will now see a visual of the two tables.
1. Drag the customer field from the customersentimentsept2022 table onto the customer field of salesept2022.
1. In the Create Relationship screen select Confirm.
1. At the top right of the screen select the SQL Endpoint drop-down and select Lakehouse.

## Analyze customer sentiment data with archived sales data.

Let's see if we can visualize any trends with customer sentiment captured by surveys and sales data.

1. Select New Power BI dataset at the top menu.
1. Click Select All and click Confirm
1. You will be presented with a Synapse Data Engineering page.
1. In the middle of the page select **+ Create from scratch** on the Visual this data part of the page. Select Auto-create.
1. When the Your report is ready message pops-up select View report.
1. On the right-hand side of the screen is a view of the columns of the tables. Expand both and unselect any columns selected.
1. We want to see relationships between sentiment for both product and salespersons and sales.
1. For the salessept2022 table select the customer, sales_amount (use the Sum option), and salesperson fields. For cusgtomersentimentsept2022 select customer, productsentiment, and salespersonsentiment.
1. You can now analyze any trend data. There are 6 visuals to view.
1. In the upper left view we can see Customer_1 and Customer_3 have the highest sales. Click on Customer_1. You can see Customer_1 has SalesPeron1 and sentiment is Excellent across the board.
1. Customer_3 also is for SalesPerson1 and has Good Product Sentiment but Excellent SalesPerson sentiment.
1. Customer_2 has lower sales and Negative Product sentiment but Good SalesPerson sentiment and also belongs to SalesPerons1
1. Looking at Customer_4 you can see SalesPerson2 is assigned and even though the ProductSentiment is good the SalesPerson sentiment is Negative.
1. Customer_5 also has lower sales with the same trend.