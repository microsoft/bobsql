USE ContosoHR;
GO
-- You cannot turn off versioning for a ledger table
ALTER TABLE Employees SET (SYSTEM_VERSIONING = OFF);
GO
-- You cannot drop the ledger history table
DROP TABLE dbo.MSSQL_LedgerHistoryFor_901578250;
GO
-- You can drop a ledger table
DROP TABLE Employees;
GO
-- But we keep a history of the dropped table
SELECT * FROM sys.objects WHERE name like '%DroppedLedgerTable%';
GO
-- You cannot drop the "dropped ledger table". Substitue the table name from the results from the previous query
DROP TABLE MSSQL_DroppedLedgerTable_Employees_5363A044DD864F90BF64B81441A0B9DC;
GO
