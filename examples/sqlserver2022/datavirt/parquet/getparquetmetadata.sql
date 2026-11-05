USE [WideWorldImporters];
GO
EXEC sp_describe_first_result_set N'
SELECT *
FROM OPENROWSET
	(BULK ''/wwi/''
	, FORMAT = ''PARQUET''
	, DATA_SOURCE = ''s3_wwi'')
as [wwi_customer_transactions_file];';
GO