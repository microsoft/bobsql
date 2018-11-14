-- Find out what queries hash to the same value but are different in cache
--
SELECT dest.text, deqs.query_hash, count (*) query_count
FROM sys.dm_exec_query_stats deqs
CROSS APPLY sys.dm_exec_sql_text(deqs.sql_handle) AS dest
GROUP BY (query_hash), dest.text
ORDER BY query_count DESC
GO
