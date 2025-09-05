USE [AdventureWorks];
GO
EXEC find_relevant_products_vector_search
@prompt = N'Show me stuff for extreme outdoor sports',
@stock = 100, 
@top = 20;
GO

