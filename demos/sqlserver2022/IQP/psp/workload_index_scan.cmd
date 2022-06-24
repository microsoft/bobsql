"c:\Program Files\Microsoft Corporation\RMLUtils\ostress" -E -Q"ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;" -n1 -r1 -q -oworkload_wwi_regress -dWideWorldImporters
"c:\Program Files\Microsoft Corporation\RMLUtils\ostress" -E -Q"EXEC Warehouse.GetStockItemsbySupplier 4;" -n1 -r1 -q -oworkload_wwi_regress -dWideWorldImporters

