USE AdventureWorks;
GO
SELECT 
    qsqt.query_sql_text,
    qsp.plan_id,
    qsp.query_id,
    rs.avg_duration,
    rs.count_executions
FROM 
    sys.query_store_query_text AS qsqt
JOIN 
    sys.query_store_query AS qsq
    ON qsqt.query_text_id = qsq.query_text_id
JOIN 
    sys.query_store_plan AS qsp
    ON qsq.query_id = qsp.query_id
JOIN 
    sys.query_store_runtime_stats AS rs
    ON qsp.plan_id = rs.plan_id
GROUP BY qsqt.query_sql_text, qsp.plan_id, qsp.query_id, rs.avg_duration, rs.count_executions
ORDER BY 
    rs.avg_duration DESC;
GO