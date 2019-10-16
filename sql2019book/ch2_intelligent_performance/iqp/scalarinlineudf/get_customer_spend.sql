USE WideWorldImportersDW
GO
SELECT c.[Customer Key], SUM(oh.[Total Including Tax]) as total_spend
FROM [Fact].[OrderHistory] oh
JOIN [Dimension].[Customer] c 
ON oh.[Customer Key] = c.[Customer Key]
GROUP BY c.[Customer Key]
ORDER BY total_spend DESC
GO