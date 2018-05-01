My demo machine specs

HP Studio ZBook Studio G3

32Gb RAM

4 core socket HT (8 logical CPUs)

512Gb SSD PCI NVMe SAMSUNG MZVPV512HDGL-000H1 (C: Drive) 

1TB SSD PCI NVMe THNSN51T02DU7 TOSHIBA (D: Drive) - Note: Turn off Windows write-cache buffer flushing policy is ON for this drive

Windows 10 - Version 1703 (OS Build 15063.540)

SQL Server 2017 RTM installed on Windows 10

Virtual Machine running RHEL 7.4 Enterprise with SQL Server 2017 installed (8 virtual processors and 16Gb RAM assigned to VM). I installed the VM on the D: for maximum I/O performance.

PowerBI Desktop Installed on Windows

RML Utilities - https://www.microsoft.com/en-us/download/details.aspx?id=4511 (and you need to put the installation of this in the path so ostress.exe can be recognized from any command prompt. By default it is installed at C:\Program Files\Microsoft Corporation\RMLUtils)

Be sure to shutdown any SQL Server instances on your host laptop to ensure the RHEL VM can start (to give it enough memory)

The sa password on my Linux installation is Sql2017isfast

For my SQL Linux VM I created a static IP address for the VM and mapped this to bwsql2017rhel in the hosts file on Windows

This assumes you have installed PowerBI for Desktop on Windows 10 which can be found at https://www.microsoft.com/en-us/download/details.aspx?id=45331

1. Run create_tpch_workload.cmd from the tpch_workload and tpch_workload_faster directories to install 2 SQL Server databases on a SQL Server installation on Linux if you have not already done so.

I use these directories on Linux for the input files

/var/opt/mssql/tpch_workload

/var/opt/mssql/tpch_workload_faster

2. Open up powerbi_tpch_workload.pbix on Windows

Refresh the visual map by right-clicking on the shipping_priority data source and selecting Refresh. Notice this just takes a second or two

Simulate multiple users running the query that feeds shipping_priority by running runpowerbi_query_3.cmd. This script takes 4 parameters: SQL Linux Instance, SA pwd, database name, # users

Ex from powershell

.\runpowerbi_query_3 bwsql2017rhel Sql2017isfast tpch_workload 10

Try to refresh shipping_priority again and notice how long it takes.

Stop the ostress session

3. Let's see how SQL Server handles building an ad-hoc PowerBI visual

Drag the C_MKTSEGMENT from CUSTOMER onto the PowerBI canvas

Now drag the L_QUANTITY from LINEITEM into that same visual

Note how long it takes to build

Change the visual to a pie chart

Change the visual to various other types and notice the performance

4. Leave all this up and load up the powerbi_tpch_workload_faster.pbix file

Go the same steps 2-3 above except use tpch_workload_faster with the command script

.\runpowerbi_query_3 bwsql2017rhel Sql2017isfast tpch_workload_faster 10

Note the performance crispness. This database is using clustered columnstore indexes for the two big "fact" tables which are LINEITEM and ORDERS

5. Three of the reasons for great performance we talked about our compression, rowgroup elimination, and batch operations

Notice the number in the lower right hand of the canvas. That is db size. Notice with CCI it compresses to 50%  of the size of the database without columnstore

Bring up the powerbi_qdb_query_3.sql in SSMS and observe its execution plan. Note two things

The CCI scan operations using Batch

The XML shows SegmentReads and SegmentSkips. The skips are the rowgroup elimination

One of the keys to getting these skips was to build a clustered index for both of these tables on the date columns and then build a CCI on top of these with DROP_EXISTING. So the segments are based on date time rangessince most of the expensive queries in TPC-H are always looking a date ranges