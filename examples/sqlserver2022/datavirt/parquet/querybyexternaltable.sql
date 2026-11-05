USE [WideWorldImporters];
GO
IF OBJECT_ID('wwi_customer_transactions_base', 'U') IS NOT NULL
	DROP EXTERNAL TABLE wwi_customer_transactions_base;
GO
CREATE EXTERNAL TABLE wwi_customer_transactions_base 
( 
	CustomerTransactionID int, 
	CustomerID int,
	TransactionTypeID int,
	TransactionDate date,
	TransactionAmount decimal(18,2)
)
WITH 
(
	LOCATION = '/wwi/'
    , FILE_FORMAT = ParquetFileFormat
    , DATA_SOURCE = s3_wwi
);
GO
SELECT * FROM wwi_customer_transactions_base;
GO