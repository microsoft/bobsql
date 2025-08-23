USE master;
GO

DROP DATABASE IF EXISTS hr;
GO

CREATE DATABASE hr;
GO

USE hr;
GO

-- Create an employees table with checks for valid email addresses
-- For Phone Numbers you must enforce this format type of format 
-- which cannot be done with LIKE such as (123) 456-7890
DROP TABLE IF EXISTS EMPLOYEES;
GO
CREATE TABLE EMPLOYEES (  
    ID INT IDENTITY(101,1),  
    [Name] VARCHAR(150),  
    Email VARCHAR(320)  
    CHECK (REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),  
    Phone_Number NVARCHAR(20)  
    CHECK (REGEXP_LIKE(Phone_Number, '^\(\d{3}\) \d{3}-\d{4}$'))  
);
GO
