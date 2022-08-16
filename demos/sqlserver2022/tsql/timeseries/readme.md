# Time Series T-SQL functions in SQL Server 2022

Follow these steps to demonstrate new time series T-SQL functions in SQL Server 2022. Credits to Kendal Van Dyke for giving me the base for these demos.

## Prerequisites

- SQL Server 2022 Evaluation Edition
- VM or computer with 2 CPUs and at least 8Gb RAM.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.

## Steps for the demo

1. Execute the script **date_bucket.sql** to see how to use the DATE_BUCKET() function.
1. Execute the script **generate_series.sql** to see how to use the GENERATE_SERIES() function.
1. Execute the script **setup_gapfilling.sql** to setup the gap filling demo.
1. Execute the script **gap_filling.sql** to see how to use the FIRST_VALUE() and LAST_VALUE() functions.