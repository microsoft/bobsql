SELECT top 70 counter_name, [retrieval_time],
              CASE WHEN LAG(cntr_value,1) OVER (ORDER BY [retrieval_time]) IS NULL THEN  
                     cntr_value-cntr_value
                     ELSE cntr_value - LAG(cntr_value,1) OVER (ORDER BY [retrieval_time]) END AS cntr_value
FROM ##tblPerfCount
ORDER BY [retrieval_time] DESC
GO
