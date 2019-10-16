-- Step 1: Clear the procedure cache and set dbcompat to 130 to prove you don't need 150 for last plan stats
USE WideWorldImporters
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO
ALTER DATABASE [WideWorldImporters] SET COMPATIBILITY_LEVEL = 130
GO
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON
GO
SELECT COUNT(*) FROM Sales.InvoiceLinesExtended
GO

-- Step 2: Simulate a statistic out of date to a really low value
UPDATE STATISTICS Sales.InvoiceLinesExtended
WITH ROWCOUNT = 1
GO

-- Step 3: Run a query. This should only take a few seconds but it is all CPU
SELECT si.InvoiceID, sil.StockItemID
FROM Sales.InvoiceLinesExtended sil
JOIN Sales.Invoices si
ON si.InvoiceID = sil.InvoiceID
AND sil.StockItemID >= 225
GO

-- Step 4: What does the estimated plan say? Looks like the right plan based on estimates
SELECT st.text, cp.plan_handle, qp.query_plan
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE qp.dbid = db_id('WideWorldImporters')
GO

-- Step 5: What does the last actual plan say? Ooops. Actual vs Estimates way off
SELECT st.text, cp.plan_handle, qps.query_plan, qps.*
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan_stats(cp.plan_handle) AS qps
WHERE qps.dbid = db_id('WideWorldImporters')
GO

-- Step 6: Update stats to the correct value and clear proc cache
UPDATE STATISTICS Sales.InvoiceLinesExtended
WITH ROWCOUNT = 3652240
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO

-- Step 7: Run the query again. Faster
SELECT si.InvoiceID, sil.StockItemID
FROM Sales.InvoiceLinesExtended sil
JOIN Sales.Invoices si
ON si.InvoiceID = sil.InvoiceID
AND sil.StockItemID >= 225
GO

-- Step 8: What does the actual plan look like now? Different because stats are up to date
SELECT st.text, cp.plan_handle, qps.query_plan
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan_stats(cp.plan_handle) AS qps
WHERE qps.dbid = db_id('WideWorldImporters')
GO

-- Step 9: Restore dbcompat
ALTER DATABASE [WideWorldImporters] SET COMPATIBILITY_LEVEL = 150
GO