-- Use FIRST_VALUE and LAST_VALUE to fill in gaps
USE GapFilling;
GO
SELECT timestamp
	   , VoltageReading
	   , FIRST_VALUE (VoltageReading) IGNORE NULLS OVER (
			ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING 
			) AS [FIRST_VALUE]
		, LAST_VALUE (VoltageReading) IGNORE NULLS OVER (
			ORDER BY timestamp DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW 
			) AS [LAST_VALUE]
FROM MachineTelemetry
ORDER BY [timestamp];
GO