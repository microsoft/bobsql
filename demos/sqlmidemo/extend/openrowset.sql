-- Query on a file of parquet files stored in a publicly available storage account:
SELECT *
FROM OPENROWSET(
BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2001/puMonth=1',
FORMAT = 'parquet'
) AS taxidata;
GO
-- How many parquet files are in the folder?
SELECT files.filepath()
FROM OPENROWSET(
BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2001/puMonth=1',
FORMAT = 'parquet'
) AS files;
GO
