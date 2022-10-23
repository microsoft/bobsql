# Surface Area T-SQL functions in SQL Server 2022

Follow these steps to demonstrate T-SQL enhancements across the core SQL engine in SQL Server 2022

## Prerequisites

- SQL Server 2022 Evaluation Edition
- VM or computer with 2 CPUs and at least 8Gb RAM.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.
- To run the demo for isnotdistinct.sql you will need to restore the WideWorldImporters sample back from https://aka.ms/WideWorldImporters.

##  Steps to run the demos

1. Execute the script **datetrunc.sql** to see how the new DATETRUNC() function works.
1. Execute the script **greatest_least.sql** to see how the new GREATEST() and LEAST() functions work.
1. Execute the script **string_split.sql** to see how the enhanced STRING_SPLIT() functions works.
1. *Examine* the script **window.sql** to see how the new WINDOW clause works.
1. After restoring the WideWorldImporters database, execute the script **setup_isnotdistinct.sql**.
1. Execute the script **isnotdistinct.sql** to see how the IS NOT DISTINCT FROM T-SQL statements works.