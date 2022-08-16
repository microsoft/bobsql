-- This is a demo for the new DATETRUNC() T-SQL function in SQL Server 2022
-- Truncate just the year from a date with a variable
DECLARE @d date = '2022-05-14';
SELECT DATETRUNC(year, @d);                                                                  
GO
-- Truncate the hour from a granular datetime value
SELECT DATETRUNC(hour, '1963-12-29 02:04:23.1234567');
GO
-- Truncate to the day of the year
SELECT DATETRUNC(dayofyear, '1996-03-27 10:10:05');
GO
-- Truncate to the quarter of the year
SELECT DATETRUNC(Quarter, '1993-08-30 11:10:01');
GO