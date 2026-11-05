USE ContosoHR;
GO
-- Use * for all columns
SELECT * FROM dbo.Employees;
GO
-- List out all the columns
SELECT EmployeeID, SSN, FirstName, LastName, Salary, 
ledger_start_transaction_id, ledger_end_transaction_id, ledger_start_sequence_number, 
ledger_end_sequence_number
FROM dbo.Employees;
GO