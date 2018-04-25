This is a demo to show security features of SQL Server. The demo assumes you have restored the WideWorldImporters sample database from XXXXX

Dynamic Data Masking

This demo is based on the sample script provided at https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/wide-world-importers/sample-scripts/dynamic-data-masking

1. Open up the file dynamic_data_masking.sql and connect to the WideWorldImporters sample

2. Follow the instructions in the comments in the script.

3. To clean up the demo execute the commented instructions at the end of the script file

Vulnerability Assessment

This demo assumes you have installed SQL Server Management Studio (SSMS) on a Windows computer from https://docs.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-2017

1. Connect to your SQL Server on Linux with SSMS

2. Right-click the Server In Object Explorer and pick Tasks/Vulnerability Assessment/Scan for Vulnerabilities

3. Click OK on the next screen

4. Review the Assessment Results. Click on individual items to see details. Notice you can approve some flagged rules as "Baselines" to accept them and they will be ignored in the future

Classify Data

This demo assumes you have installed SQL Server Management Studio (SSMS) on a Windows computer from https://docs.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-2017

1. Connect to your SQL Server on Linux with SSMS

2. Right-click the Server In Object Explorer and pick Tasks/Classify Data

3. At top of new screen select "...classification recommendations (click to view)"

4. Scroll and see the types of choices for Information Type and Sensitivity Label. This functionality is based on the Extended Properties feature in the SQL Server Engine.



