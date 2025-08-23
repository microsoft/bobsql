USE master;
GO

DROP DATABASE IF EXISTS hr;
GO

CREATE DATABASE hr;
GO

USE hr;
GO

-- Create an employees table with checks for valid email addresses and phone numbers
-- With check that cannot be done with LIKE
DROP TABLE IF EXISTS EMPLOYEES;
GO
CREATE TABLE EMPLOYEES (  
    ID INT IDENTITY PRIMARY KEY CLUSTERED,  
    [Name] VARCHAR(150),  
    Email VARCHAR(320)  
    CHECK (REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),  
    PhoneNumber NVARCHAR(20)  
    CHECK (REGEXP_LIKE(PhoneNumber,'^\+\d{1,3}[ -]?(?:\([2-9]\d{2}\)[ -]?\d{3}-\d{4}|[2-9]\d{2}[ -]?\d{3}-\d{4})$')
    )
);  
GO
