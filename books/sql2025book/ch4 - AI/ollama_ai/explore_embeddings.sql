USE AdventureWorks;
GO

SELECT TOP 20 p.ProductID, p.Name, pd.Description, pde.Embedding 
FROM Production.ProductDescriptionEmbeddings pde
JOIN Production.Product p
ON pde.ProductID = p.ProductID
JOIN Production.ProductDescription pd
ON pd.ProductDescriptionID = pde.ProductDescriptionID
GO