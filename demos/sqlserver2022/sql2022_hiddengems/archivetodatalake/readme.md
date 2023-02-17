# Demo to use Data Virtualization to archive partitioned tables into a data lake

This is a demo to use SQL Server 2022 data virtualiztion to archive partitions from a table considered "cold data" into a data lake but access like a table

## Setup

1. Install SQL Server 2022. You must enable the Polybase feature
2. Using your Azure subscription create an Azure Storage account using these steps https://learn.microsoft.com/azure/storage/blobs/create-data-lake-storage-account.
3. Create a container for the storage account using these steps: https://learn.microsoft.com/azure/storage/blobs/blob-containers-portal. Note you can leave access as Private.
4. Executed the script enablepolybase.sql
5. Read through the details in salesddl.sql and execute all the T-SQL in the script. You now have a database with a partitioned table for Sales Data partitioned by date ranges.
6. Created a Shared Access Signature (SAS) for the Azure Storage Account. To get tips on creating this and setting the right access see the doc page at https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-data-source-transact-sql. Look down at the section for arguents titled CREDENTIAL=credential_name.
7. Edit the script ddl_datalake.sql to put in your proper storage account name, container, and Shared Access Signature. Execute the script ddl_datalake.sql to setup external data sources and file formats.

## Archive cold data to a data lake

1. Execute the script archive_table.sql to move a partition to the archive table and then export the archive table to the data lake.
2. Check the Azure Portal for your container to make sure the new folder and parquet file exist.
3. Execute the script getarchivesept2022.sql to query the archive files through the external table, union with existing Sales table, and truncate the archive table.