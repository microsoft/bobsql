USE hr;
GO

-- Valid INSERT
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Dak Prescott', 'dak.prescott@example.com', '(123) 456-7890');
GO

-- Invalid INSERT
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Jerry Jones', 'jerry.jones@example.com', '123-456-7890');
GO
