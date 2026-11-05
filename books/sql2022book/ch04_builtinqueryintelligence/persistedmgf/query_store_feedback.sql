SELECT qt.query_sql_text, qpf.feedback_data
FROM sys.query_store_query_text qt
JOIN sys.query_store_query qq
ON qt.query_text_id = qq.query_text_id
JOIN sys.query_store_plan qp
ON qq.query_id = qp.query_id
JOIN sys.query_store_plan_feedback qpf
ON qp.plan_id = qpf.plan_id;
GO