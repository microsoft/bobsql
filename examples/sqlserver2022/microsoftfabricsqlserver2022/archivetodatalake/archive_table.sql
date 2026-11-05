USE SalesDB;
GO
-- Switch partition 1 into the Sales Archive table
--
ALTER TABLE Sales
SWITCH PARTITION 1 TO SalesArchive;
GO
SELECT * FROM SalesArchive;
GO
-- Create external table to export to Parquet from SalesArchive
--
CREATE EXTERNAL TABLE SalesArchiveSept2022
WITH (
LOCATION = '/salessept2022',
DATA_SOURCE = bwdatalake,
FILE_FORMAT = ParquetFileFormat
)
AS
SELECT * FROM SalesArchive;
GO