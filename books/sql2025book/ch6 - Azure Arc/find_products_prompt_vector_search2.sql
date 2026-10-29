USE [AdventureWorks];
GO
EXEC find_relevant_products_vector_search2
@prompt = N'Products best for rides on rough ground',
@stock = 100, 
@top = 20;
GO

-- Do the same prompt but in Chinese
USE [AdventureWorks];
GO
EXEC find_relevant_products_vector_search2
@prompt = N'适合在崎岖地面上骑行的最佳产品', 
@stock = 100, 
@top = 20;
GO
