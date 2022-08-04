USE [WideworldImporters];
GO
CREATE EXTERNAL TABLE PEOPLE10M_60s
WITH 
(   LOCATION = '/delta/1960s',
    DATA_SOURCE = s3_wwi,  
    FILE_FORMAT = ParquetFileFormat)  
AS
SELECT * FROM OPENROWSET
(BULK '/delta/people-10m', FORMAT = 'DELTA', DATA_SOURCE = 's3_wwi') as [people]
WHERE YEAR(people.birthDate) > 1959 AND YEAR(people.birthDate) < 1970;
GO