USE [AdventureWorks];
GO

EXEC find_relevant_products_vector_search
@prompt = N'Show me stuff for extreme outdoor sports',
@stock = 100, 
@top = 20;
GO


-- Do the same prompt but in Chinese
EXEC find_relevant_products_vector_search
@prompt = N'请向我展示极限户外运动的装备',
@stock = 100,
@top = 20;
GO

