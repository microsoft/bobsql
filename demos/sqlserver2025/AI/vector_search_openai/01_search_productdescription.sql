USE AdventureWorks;
GO
SELECT * FROM Production.ProductDescription
WHERE Description LIKE '%pillow-y%'
GO
SELECT * FROM Production.ProductDescription
WHERE CONTAINS(Description, '"zero buzz"');
GO
SELECT * FROM Production.ProductDescription
WHERE FREETEXT(Description, 'I want a gliding, pillow‑y feel on battered streets, zero buzz through the hands');
GO

