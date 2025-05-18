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

-- Valid INSERT
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Dak Prescott', 'dak.prescott@example.com', '(123) 456-7890');
GO

-- Invalid INSERT
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Jerry Jones', 'jerry.jones@example.com', '123-456-7890');
GO


INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('LeBron James', 'lebron.james@basketball.com', '(234) 567-8901');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Serena Williams', 'serena.williams@tennis.org', '(345) 678-9012');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Lionel Messi', 'lionel.messi@soccer.net', '(456) 789-0123');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Tom Brady', 'tom.brady@football.co', '(567) 890-1234');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Roger Federer', 'roger.federer@tennis.com', '(678) 901-2345');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Simone Biles', 'simone.biles@gymnastics.org', '(789) 012-3456');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Cristiano Ronaldo', 'cristiano.ronaldo@soccer.co', '(890) 123-4567');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Michael Phelps', 'michael.phelps@swimming.net', '(901) 234-5678');
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Usain Bolt', 'usain.bolt@track.com', '(012) 345-6789');
GO

-- Do a complex search. Find any eamil where the word "will" appears after the "." in an eamil address and ends in .org
/* ^[^@]+: Matches one or more characters that are not the "@" symbol at the start of the string.
\.: Matches the literal dot character ".".
[^.]*will: Matches zero or more characters that are not the dot character, followed by "will". This ensures "will" appears somewhere after the first dot.
.*: Matches any character (except for line terminators) zero or more times. It allows for any characters to appear after "will".
\.: Matches the literal dot character ".".
org: Matches the exact sequence "org".
$: Asserts the position at the end of the string. */

SELECT * FROM EMPLOYEES
WHERE REGEXP_LIKE(Email, '^[^@]+\.[^.]*will.*\.org$');
GO




