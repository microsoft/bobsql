-- This is a demo for the new DATETRUNC() T-SQL function in SQL Server 2022
-- Credits to Aashna Bafna for providing the base for these demos
-- Step 1: Truncate just the year from a date with a variable
USE master;
GO
DECLARE @d date = '2022-05-14';
SELECT DATETRUNC(year, @d);                                                                  
GO
-- Step 2: Truncate the hour from a granular datetime value
USE master;
GO
SELECT DATETRUNC(hour, '1963-12-29 02:04:23.1234567');
GO
-- Step 3: Truncate to the day of the year
USE master;
GO
SELECT DATETRUNC(dayofyear, '1996-03-27 08:05:30');
GO
-- Step 4: Truncate to the quarter of the year using a date type
USE master;
GO
DECLARE @date date = '1993-08-30'
SELECT DATETRUNC(Quarter, @date);
GO