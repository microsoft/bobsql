USE [WideWorldImporters];
GO
SELECT *
FROM OPENROWSET
	(BULK '/wwi/'
	, FORMAT = 'PARQUET'
	, DATA_SOURCE = 's3_wwi')
as [wwi_customer_transactions_file];
GO
