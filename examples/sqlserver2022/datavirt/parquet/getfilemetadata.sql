USE [WideWorldImporters];
GO
SELECT TOP 1 wwi_customer_transactions_file.filepath(), 
wwi_customer_transactions_file.filename()
FROM OPENROWSET
	(BULK '/wwi/'
	, FORMAT = 'PARQUET'
	, DATA_SOURCE = 's3_wwi')
as [wwi_customer_transactions_file];
GO
