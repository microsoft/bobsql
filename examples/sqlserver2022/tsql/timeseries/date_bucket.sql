-- Step 1: Calculate DATE_BUCKET with a bucket width of 1 with various dateparts
USE master;
GO
DECLARE @date DATETIME = '2022-05-14 13:30:05';
SELECT 'Now' AS [BucketName], @date AS [DateBucketValue]
UNION ALL
SELECT 'Year', DATE_BUCKET (YEAR, 1, @date)
UNION ALL
SELECT 'Quarter', DATE_BUCKET (QUARTER, 1, @date)
UNION ALL
SELECT 'Month', DATE_BUCKET (MONTH, 1, @date)
UNION ALL
SELECT 'Week', DATE_BUCKET (WEEK, 1, @date)
UNION ALL
SELECT 'Day', DATE_BUCKET (DAY, 1, @date)
UNION ALL
SELECT 'Hour', DATE_BUCKET (HOUR, 1, @date)
UNION ALL
SELECT 'Minutes', DATE_BUCKET (MINUTE, 1, @date)
UNION ALL
SELECT 'Seconds', DATE_BUCKET (SECOND, 1, @date);
GO
-- Step 2: Use a date instead of datetime
USE master;
GO
DECLARE @date DATE = '2022-05-14';
SELECT DATE_BUCKET(week, 1, @date);
GO
-- Step 3: Generate fixed bucket sizes
USE master;
GO
DECLARE @dt DATETIME = '2022-05-14 13:35:12';
SELECT '5 Minute Buckets' AS [BucketName], DATE_BUCKET (MINUTE, 5, @dt)
UNION ALL
SELECT 'Quarter Hour', DATE_BUCKET (MINUTE, 15, @dt);
GO
