SELECT pgd.datname, rsv.query_id, rsv.total_time/qsv.calls as avg_time, rsv.total_time, rsv.blk_read_time, rsv.blk_write_time, rsv.calls, qsv.query_sql_text, qpv.plan_text
FROM query_store.runtime_stats_view rsv
JOIN pg_database pgd
ON rsv.db_id = pgd.oid
JOIN query_store.qs_view qsv
ON rsv.query_id = qsv.query_id
JOIN query_store.query_plans_view qpv
ON qpv.plan_id = rsv.plan_id
WHERE pgd.datname = 'pgbench'
AND qsv.query_type != 'nothing'
ORDER BY avg_time DESC;