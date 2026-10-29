SELECT fo.[Order Key], fo.Description, si.[Lead Time Days]
FROM  Fact.OrderHistory AS fo
INNER JOIN Dimension.[Stock Item] AS si 
ON fo.[Stock Item Key] = si.[Stock Item Key]
WHERE fo.[Lineage Key] = 9
AND si.[Lead Time Days] > 19
ORDER BY fo.[Order Key], fo.Description, si.[Lead Time Days]
OPTION (MAXDOP 1)
GO
