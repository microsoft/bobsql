-- This is a demo for the new GREATEST and LEAST T-SQL functions in SQL Server 2022
-- Step 1: A simple set of numbers
USE master;
GO
SELECT GREATEST(6.5, 3.5, 7) as greatest_of_numbers;
GO
-- Step 2: Does it work even if datatypes are not the same?
USE master;
GO
SELECT GREATEST(6.5, 3.5, N'7') as greatest_of_values;
GO
-- Step 3: What about strings?
USE master;
GO
SELECT GREATEST('Buffalo Bills', 'Cleveland Browns', 'Dallas Cowboys') as the_best_team
GO
-- Step 4: Use it in a comparison
USE master;
GO
DROP TABLE IF EXISTS studies;
GO
CREATE TABLE studies (    
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
-- Step 5: Simple LEAST example
USE master;
GO
SELECT LEAST(6.5, 3.5, 7) as least_of_numbers;
GO
-- Step 6: Combine with variables
USE master;
GO
DECLARE @VarX decimal(4, 3) = 0.59;  
SELECT VarX, Correlation, LEAST(Correlation, 1.0, @VarX) AS LeastVar  
FROM dbo.studies;
GO
-- Clean up table
DROP TABLE IF EXISTS studies;
GO

