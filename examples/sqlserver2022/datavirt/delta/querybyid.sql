USE [WideWorldImporters];
GO
SELECT * FROM OPENROWSET
(BULK '/delta/people-10m', 
FORMAT = 'DELTA', DATA_SOURCE = 's3_wwi') as [people]
WHERE [people].id = 10000000;
GO