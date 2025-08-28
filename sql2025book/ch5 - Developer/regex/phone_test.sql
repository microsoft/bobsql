USE hr;
GO

-- Valid INSERT
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Dak Prescott', 'dak.prescott@example.com', '(214) 456-7890');
GO

-- Invalid INSERT
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Jerry Jones', 'jerry.jones@example.com', '+1 (682) 555.1212');
GO
