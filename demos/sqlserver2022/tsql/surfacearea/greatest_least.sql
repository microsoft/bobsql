-- This is a demo for the new GREATEST and LEAST T-SQL functions in SQL Server 2022
-- A simple set of numbers
SELECT GREATEST(6.5, 3.5, 7) as greatest_of_numbers;
GO
-- Does it work even if datatypes are not the same?
SELECT GREATEST(6.5, 3.5, N'7') as greatest_of_values;
GO
-- What about strings?
SELECT GREATEST('Buffalo Bills', 'Cleveland Browns', 'Dallas Cowboys') as the_best_team
GO
-- Use it in a comparison
CREATE TABLE dbo.studies (    
    VarX varchar(10) NOT NULL,    
    Correlation decimal(4, 3) NULL 
); 
INSERT INTO dbo.studies VALUES ('Var1', 0.2), ('Var2', 0.825), ('Var3', 0.61); 
GO 
DECLARE @PredictionA DECIMAL(4,3) = 0.7;  
DECLARE @PredictionB DECIMAL(4,3) = 0.65;  
SELECT VarX, Correlation  
FROM dbo.studies 
WHERE Correlation > GREATEST(@PredictionA, @PredictionB); 
GO
-- Simple LEAST example
SELECT LEAST(6.5, 3.5, 7) as least_of_numbers;
GO
-- Combine with variables
DECLARE @VarX decimal(4, 3) = 0.59;  
SELECT VarX, Correlation, LEAST(Correlation, 1.0, @VarX) AS LeastVar  
FROM dbo.studies;
GO 
