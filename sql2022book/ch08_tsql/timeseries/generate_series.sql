-- Step 1: Generate a series of integer values with a default interval of 1
USE master;
GO
SELECT value
FROM GENERATE_SERIES(1, 100);
GO
-- Step 2: Generate a series of integer values backwards with an interval of 5
USE master;
GO
SELECT value
FROM GENERATE_SERIES(100, 1, -5);
GO
-- Step 3: Generate a series of decimal values between 0 and 1.0 in increments of 0.05
USE master;
GO
SELECT value
FROM GENERATE_SERIES(0.0, 1.0, 0.05);
GO
-- Step 4: Data types must match! The first batch results in an error
-- To get around this, either explicitly cast to matching data types or use parameters
USE master;
GO
SELECT value
FROM GENERATE_SERIES(1, 10, 0.5);
GO
DECLARE @start numeric(2,1) = 1;
DECLARE @end numeric(3,1) = 10;
DECLARE @step numeric(2,1) = 0.5;
SELECT value
FROM GENERATE_SERIES(@start, @end, @step);
GO
