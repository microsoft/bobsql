/*
    Automatic Index Compaction (AIC) Demo - Step 5: Check Progress
    ==============================================================
    Monitor AIC compaction progress: density, page count, PVS size.
    Run this periodically after enabling AIC (04-enable-aic.sql).
    
    Watch for:
    - density_pct rising from ~47% toward 95%+
    - page_count dropping from ~18K toward ~8.9K
    - pvs_kb shrinking as version cleanup completes
*/

/* AIC enabled? */
SELECT name AS database_name,
       IIF(is_automatic_index_compaction_on = 1, 'ON', 'OFF') AS aic_status
FROM sys.databases
WHERE database_id = DB_ID();
GO

/* Index physical stats + PVS */
SELECT CAST(ips.avg_page_space_used_in_percent AS decimal(5,2)) AS density_pct,
       ips.page_count,
       ips.record_count,
       CAST(ips.avg_fragmentation_in_percent AS decimal(5,2)) AS frag_pct,
       pvs.persistent_version_store_size_kb AS pvs_kb
FROM sys.dm_db_index_physical_stats(
    DB_ID(), OBJECT_ID('dbo.aic_demo'), 1, 1, 'DETAILED') AS ips
CROSS JOIN sys.dm_tran_persistent_version_store_stats AS pvs
WHERE ips.index_level = 0
      AND pvs.database_id = DB_ID();
GO
