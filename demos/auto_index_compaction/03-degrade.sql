/*
    Automatic Index Compaction (AIC) Demo - Step 2: Degrade
    =======================================================
    Scatter-delete 50% of rows using CHECKSUM modulo.
    Every page loses roughly half its rows, but no page goes empty.
    Result: ~47% page density, same page count — worst case for scans.

    Why CHECKSUM(id) % 2?
    - Distributes deletes uniformly across all pages (not contiguous).
    - Contiguous deletes would deallocate entire pages (no density problem).
    - Scatter-delete leaves every page half-full — maximum wasted I/O.

    Note: In Hyperscale (ADR), the DELETE stamps a 14-byte version pointer
    on each ghost record. Pages at 99.8% density may split from this overhead,
    which is why page count can increase slightly after the delete.
*/

/* Scatter-delete: remove rows where CHECKSUM(id) is even */
DELETE dbo.aic_demo WHERE CHECKSUM(id) % 2 = 0;
GO

/* Verify degradation */
SELECT CAST(avg_page_space_used_in_percent AS decimal(5,2)) AS density_pct,
       page_count,
       record_count AS rows_remaining
FROM sys.dm_db_index_physical_stats(
    DB_ID(), OBJECT_ID('dbo.aic_demo'), 1, 1, 'DETAILED')
WHERE index_level = 0;
GO

PRINT 'Degradation complete. ~50% of rows deleted, pages still allocated.';
PRINT 'Next: run scan-test.sql to measure DEGRADED cold-cache scan, then 04-enable-aic.sql.';
GO
