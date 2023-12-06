SELECT pgd.datname, qsv.query_id, qsv.total_time, qsv.blk_read_time, qsv.blk_write_time, qsv.calls, qsv.query_type, qsv.query_sql_text
FROM query_store.qs_view qsv
JOIN pg_database pgd
ON qsv.db_id = pgd.oid
WHERE pgd.datname = 'pgbench'
AND qsv.calls > 1
AND qsv.query_type != 'nothing'
ORDER BY qsv.total_time/qsv.calls DESC;