
-- CPU-bound: transcendental math (fast to generate rows, no table I/O)
WITH n AS (
    SELECT TOP (2000000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
SELECT SUM(ABS(SIN(i*0.0007)) + ABS(COS(i*0.0003)) + LOG(i+1) + SQRT(i)) AS s
FROM n
