# Accelerated Database Recovery

In this example, you will learn how Accelerated Database Recovery (ADR) can speed up rollback and avoid transaction log growth problems for long running transactions. In addition, a more advanced example shows how Accelerated Database Recovery can speed up undo recovery.

## Requirements

All these examples run with SQL Server 2019. You can choose to run these examples with a T-SQL script using a tool like SSMS or with a T-SQL notebook with Azure Data Studio. ADR is on by default in Azure SQL Database so using the basic_adr script will not show differences since ADR cannot be disabled. ADR is not yet supported for Azure SQL Managed Instance. recovery_adr requires restarts of SQL Server cannot be used with Azure SQL. Note any of these can work with SQL Server in Azure Virtual Machine.

## Steps

There are two scenarios you can use:

**basic_adr.ipynb** and **basic_adr.sql** - These scripts allow you to see the basic differences of rollback and transaction log truncation with and without ADR.

**recovery_adr.ipynb** and **recovery_adr.sql** - These scripts allow you to see the differences in undo recovery with and without ADR.

To see a complete tutorial of how to run these scripts look at Module 04 of the SQL Server 2019 Workshop at https://aka.ms/sql2019workshop.

## Notes

You can read more about Accelerated Database Recovery at https://docs.microsoft.com/en-us/azure/sql-database/sql-database-accelerated-database-recovery.