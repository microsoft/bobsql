# Native JSON support in SQL Server 2025

This demo is to show the new native JSON support in SQL Server 2025. This includes new features to show the ability to use JSON as a data type, JSON functions, JSON operators, and a JSON index.

## Prerequisites

1. Use the prerequisites in the [SQL Server 2025 Developer Demos](../../readme.md) readme.

There is no need to restore a database. Each demo script includes code to create an example database.

## References

Find out more about SQL Server 2025 at https://aka.ms/sqlserver2025docs.

## Demo 1 - JSON data type

In this demonstration you will learn to use the new JSON data type in SQL Server 2025. This includes creating a table with a JSON column, inserting JSON data into the table, and querying the JSON data.

You will also use new JSON aggregrate functions and the JSON data type modify operator.
    
1. Load the script **json_type.sql** in SQL Server Management Studio (SSMS). Execute each step in the script to observe the results.

## Demo 2 - JSON index

In this demonstration you will learn to use the new JSON index in SQL Server 2025. This includes creating a table with a JSON column, inserting JSON data into the table, and creating a JSON index on the JSON column. You will then learn to query the JSON data using T-SQL functions that use the JSON index.

1. Load the script **json_index.sql** in SQL Server Management Studio (SSMS). Execute each step in the script to observe the results.

**Note:** This script simulates a rowcount of 10000 for the JSON index so it will be used. JSON indexes may not be used by the optimizer for low rowcounts so this code is added only for demo purposes to show the index being used since the script only populates a low number of rows.

2. For the last step in the script enable the option in SSMS to see the actual execution plan and observe the JSON index is used as part of the plan.