USE [WideWorldImporters];
GO
IF OBJECT_ID('wwi_customer_transactions', 'U') IS NOT NULL
	DROP EXTERNAL TABLE wwi_customer_transactions;
GO
CREATE EXTERNAL TABLE wwi_customer_transactions
WITH (
    LOCATION = '/wwi/',
    DATA_SOURCE = s3_wwi,  
    FILE_FORMAT = ParquetFileFormat
) 
AS
SELECT * FROM Sales.CustomerTransactions;
GO
