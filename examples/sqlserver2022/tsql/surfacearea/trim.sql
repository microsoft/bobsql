-- Demo to use enhancements to TRIM T-SQL functions. dbcomapt 160 required (which is the defualt for master on SQL Server 2022)
-- Credits to Pratim Dasgupta from Microsoft for these examples.
-- Step 1: Use new extensions for the TRIM functions
USE master;
GO
-- The first statement is what was previously only supported
SELECT TRIM('STR' FROM 'STRmydataSTR') as trim_strings;
SELECT TRIM(LEADING 'STR' FROM 'STRmydataSTR') as leading_string;
SELECT TRIM(TRAILING 'STR' FROM 'STRmydataSTR') as trailing_string;
-- Same as the previous release behavior but explicitly specifying BOTH
SELECT TRIM(BOTH 'STR' FROM 'STRmydataSTR') as both_strings_trimmed;
GO
-- Step 2: Use the new extension to the LTRIM function
USE master;
GO
SELECT LTRIM('STRmydataSTR', 'STR') as left_trimmed_string;
GO
-- Step 3: Use the new extension to the RTRIM function
USE master;
GO
SELECT RTRIM('STRmydataSTR', 'STR') as right_trimmed_string;
GO

