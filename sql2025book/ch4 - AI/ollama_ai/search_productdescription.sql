USE AdventureWorks;
GO
SELECT * FROM Production.ProductDescription
WHERE Description LIKE '%Show me stuff for extreme outdoor sports%'
GO
SELECT * FROM Production.ProductDescription
WHERE CONTAINS(Description, '"Show me stuff for extreme outdoor sports"');
GO
SELECT * FROM Production.ProductDescription
WHERE FREETEXT(Description, 'Show me stuff for extreme outdoor sports');
GO